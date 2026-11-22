#include "preview.h"
#include "flatpakops.h"

#include <QCoreApplication>
#include <QPointer>
#include <QProcess>
#include <QRegularExpression>
#include <QThread>

#include <gio/gio.h>

namespace
{
void runPacman(QObject *context, const QStringList &args, std::function<void(int, const QString &)> done)
{
    auto *process = new QProcess(context);
    QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
    env.insert(QStringLiteral("LC_ALL"), QStringLiteral("C"));
    process->setProcessEnvironment(env);
    process->setProcessChannelMode(QProcess::MergedChannels);
    QObject::connect(process, &QProcess::finished, context, [process, done](int code) {
        process->deleteLater();
        done(code, QString::fromUtf8(process->readAll()));
    });
    process->start(QStringLiteral("pacman"), args);
}

// «155.41 MiB» → байты.
qint64 parseSize(const QString &text)
{
    const QStringList parts = text.trimmed().split(u' ', Qt::SkipEmptyParts);
    if (parts.size() < 2)
        return 0;
    const double value = QString(parts[0]).replace(u',', u'.').toDouble();
    const QString unit = parts[1];
    const double scale = unit.startsWith(u'K') ? 1024.0 : unit.startsWith(u'M') ? 1024.0 * 1024 : unit.startsWith(u'G') ? 1024.0 * 1024 * 1024 : 1.0;
    return qint64(value * scale);
}
} // namespace

Preview::Preview(QObject *parent)
    : QObject(parent)
{
}

Preview::~Preview()
{
    if (m_cancellable) {
        g_cancellable_cancel(m_cancellable);
        g_object_unref(m_cancellable);
    }
}

void Preview::load(const QVariantMap &app)
{
    m_key = app.value(QStringLiteral("id")).toString();
    m_arch.clear();
    m_flathub.clear();
    if (m_cancellable) {
        g_cancellable_cancel(m_cancellable);
        g_object_unref(m_cancellable);
        m_cancellable = nullptr;
    }
    for (const QVariant &v : app.value(QStringLiteral("sources")).toList()) {
        const QVariantMap source = v.toMap();
        const bool installed = source.value(QStringLiteral("installed")).toBool();
        if (source.value(QStringLiteral("kind")) == QLatin1String("arch")) {
            const QString package = source.value(QStringLiteral("package")).toString();
            if (installed)
                loadArchRemove(package);
            else if (source.value(QStringLiteral("available")).toBool())
                loadArchInstall(package);
        } else if (!installed) {
            loadFlathub(source.value(QStringLiteral("origin")).toString(), source.value(QStringLiteral("ref")).toString());
        }
    }
    Q_EMIT changed();
}

void Preview::loadArchInstall(const QString &package)
{
    m_arch = {{QStringLiteral("loading"), true}};
    const QString key = m_key;
    QPointer<Preview> self(this);
    // Что скачается (сам пакет и недостающие зависимости).
    runPacman(this, {QStringLiteral("-Sp"), QStringLiteral("--print-format"), QStringLiteral("%n %s"), QStringLiteral("--"), package},
              [self, key, package](int code, const QString &output) {
                  if (!self || self->m_key != key)
                      return;
                  if (code != 0) {
                      self->m_arch = {{QStringLiteral("loading"), false}, {QStringLiteral("ok"), false},
                                      {QStringLiteral("error"), output.section(u'\n', 0, 0).remove(QStringLiteral("error: "))}};
                      Q_EMIT self->changed();
                      return;
                  }
                  QStringList names;
                  qint64 download = 0;
                  for (const QString &line : output.split(u'\n', Qt::SkipEmptyParts)) {
                      const QStringList parts = line.split(u' ');
                      if (parts.size() != 2)
                          continue;
                      names << parts[0];
                      download += parts[1].toLongLong();
                  }
                  QStringList extra = names;
                  extra.removeAll(package);
                  self->m_arch = {{QStringLiteral("loading"), true}, {QStringLiteral("ok"), true}, {QStringLiteral("download"), download},
                                  {QStringLiteral("extra"), extra}};
                  // Сколько займёт: «Installed Size» каждого из них.
                  runPacman(self, QStringList{QStringLiteral("-Si"), QStringLiteral("--")} + names, [self, key](int, const QString &info) {
                      if (!self || self->m_key != key)
                          return;
                      qint64 installed = 0;
                      QSet<QString> seen;
                      QString name;
                      static const QRegularExpression field(QStringLiteral("^(\\w[\\w ]*?)\\s*: (.*)$"));
                      for (const QString &line : info.split(u'\n')) {
                          const auto m = field.match(line);
                          if (!m.hasMatch())
                              continue;
                          if (m.captured(1) == QLatin1String("Name"))
                              name = m.captured(2).trimmed();
                          // Пакет бывает в нескольких репозиториях — считаем раз.
                          else if (m.captured(1) == QLatin1String("Installed Size") && !seen.contains(name)) {
                              seen.insert(name);
                              installed += parseSize(m.captured(2));
                          }
                      }
                      self->m_arch.insert(QStringLiteral("installed"), installed);
                      self->m_arch.insert(QStringLiteral("loading"), false);
                      Q_EMIT self->changed();
                  });
                  Q_EMIT self->changed();
              });
}

void Preview::loadArchRemove(const QString &package)
{
    m_arch = {{QStringLiteral("loading"), true}};
    const QString key = m_key;
    QPointer<Preview> self(this);
    runPacman(this, {QStringLiteral("-Rsp"), QStringLiteral("--print-format"), QStringLiteral("%n"), QStringLiteral("--"), package},
              [self, key, package](int code, const QString &output) {
                  if (!self || self->m_key != key)
                      return;
                  QVariantMap result{{QStringLiteral("loading"), false}};
                  if (code == 0) {
                      QStringList removes = output.split(u'\n', Qt::SkipEmptyParts);
                      removes.removeAll(package);
                      result.insert(QStringLiteral("removes"), removes);
                  } else {
                      // «removing X breaks dependency 'X' required by Y» — от
                      // пакета зависят другие: удалять нельзя.
                      static const QRegularExpression needed(QStringLiteral("required by (\\S+)"));
                      QStringList by;
                      for (auto it = needed.globalMatch(output); it.hasNext();) {
                          const QString name = it.next().captured(1);
                          if (!by.contains(name))
                              by << name;
                      }
                      result.insert(QStringLiteral("removeError"),
                                    by.isEmpty() ? output.section(u'\n', 0, 0)
                                                 : QStringLiteral("Нельзя удалить: без неё не будут работать ") + by.mid(0, 4).join(QStringLiteral(", "))
                                            + (by.size() > 4 ? QStringLiteral(" и другие") : QString()));
                  }
                  self->m_arch = result;
                  Q_EMIT self->changed();
              });
}

void Preview::loadFlathub(const QString &origin, const QString &ref)
{
    m_flathub = {{QStringLiteral("loading"), true}};
    m_cancellable = g_cancellable_new();
    GCancellable *cancellable = G_CANCELLABLE(g_object_ref(m_cancellable));
    const QString key = m_key;
    QPointer<Preview> self(this);
    QThread *thread = QThread::create([self, key, origin, ref, cancellable] {
        const FlatpakOps::Preview p = FlatpakOps::preview(origin, ref, cancellable);
        g_object_unref(cancellable);
        QMetaObject::invokeMethod(QCoreApplication::instance(), [self, key, p] {
            if (!self || self->m_key != key)
                return;
            QVariantList permissions;
            for (const auto &[text, risky] : p.permissions)
                permissions << QVariantMap{{QStringLiteral("text"), text}, {QStringLiteral("risky"), risky}};
            self->m_flathub = {
                {QStringLiteral("loading"), false},       {QStringLiteral("ok"), p.ok},
                {QStringLiteral("error"), p.error},       {QStringLiteral("download"), p.download},
                {QStringLiteral("installed"), p.installed}, {QStringLiteral("runtimes"), p.runtimes},
                {QStringLiteral("permissions"), permissions},
            };
            Q_EMIT self->changed();
        });
    });
    connect(thread, &QThread::finished, thread, &QObject::deleteLater);
    thread->start(QThread::LowPriority);
}
