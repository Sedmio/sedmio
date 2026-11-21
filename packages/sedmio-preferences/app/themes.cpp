#include "themes.h"

#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QSaveFile>
#include <QStandardPaths>

#include <algorithm>

namespace
{
QStringList themeDirs()
{
    QStringList dirs;
    for (const QString &base : QStandardPaths::standardLocations(QStandardPaths::GenericDataLocation))
        dirs << base + QStringLiteral("/sedmio/themes");
    return dirs;
}

// Ключи из разделов файла — рядом (как в модуле Sedmio.Style).
bool read(const QString &path, QVariantMap *values)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
        return false;
    const QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
    if (!doc.isObject())
        return false;
    const QJsonObject root = doc.object();
    for (auto it = root.begin(); it != root.end(); ++it) {
        if (it.value().isObject()) {
            const QJsonObject section = it.value().toObject();
            for (auto s = section.begin(); s != section.end(); ++s)
                values->insert(s.key(), s.value().toVariant());
        } else {
            values->insert(it.key(), it.value().toVariant());
        }
    }
    return true;
}

const QStringList layouts = {QStringLiteral("left"), QStringLiteral("dock"), QStringLiteral("taskbar")};

QString configDir()
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation) + QStringLiteral("/sedmio");
}

// Толщина панелей: по умолчанию и пределы — те же, что в DesktopLayout.qml.
struct PanelRange {
    const char *key;
    int def, min, max;
};
const PanelRange panelRanges[] = {
    {"left", 48, 40, 72},
    {"top", 40, 32, 56},
    {"dock", 52, 44, 96},
    {"taskbar", 44, 36, 64},
};

const PanelRange *panelRange(const QString &key)
{
    for (const PanelRange &r : panelRanges)
        if (key == QLatin1String(r.key))
            return &r;
    return nullptr;
}

// Как в оболочке: нет файла или неизвестное имя — "left"; размеры вне
// пределов не берутся.
QString readLayout(QMap<QString, int> *sizes)
{
    QFile file(configDir() + QStringLiteral("/layout"));
    if (!file.open(QIODevice::ReadOnly))
        return layouts.constFirst();
    const QString id = QString::fromUtf8(file.readLine(64)).trimmed();
    while (!file.atEnd()) {
        const QString line = QString::fromUtf8(file.readLine(256)).trimmed();
        const qsizetype eq = line.indexOf(QLatin1Char('='));
        if (eq <= 0)
            continue;
        const QString key = line.left(eq).trimmed();
        bool ok = false;
        const int value = line.mid(eq + 1).trimmed().toInt(&ok);
        const PanelRange *r = panelRange(key);
        if (ok && r && value >= r->min && value <= r->max)
            sizes->insert(key, value);
    }
    return layouts.contains(id) ? id : layouts.constFirst();
}

const QStringList previewColors = {
    QStringLiteral("paper"),      QStringLiteral("paperDeep"),  QStringLiteral("surface"),     QStringLiteral("line"),
    QStringLiteral("ink"),        QStringLiteral("inkMuted"),   QStringLiteral("green"),       QStringLiteral("textOnGreen"),
    QStringLiteral("terracotta"), QStringLiteral("windowTitle"), QStringLiteral("wallpaperTop"), QStringLiteral("wallpaperBottom"),
};
} // namespace

Themes::Themes(QObject *parent)
    : QObject(parent)
{
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, this, &Themes::rescan);
    rescan();
    m_layout = readLayout(&m_panelSizes);
    m_panelWrite.setSingleShot(true);
    m_panelWrite.setInterval(100);
    connect(&m_panelWrite, &QTimer::timeout, this, &Themes::writeLayout);
}

// Окно закрыли, пока размер ещё не записан, — записать сейчас.
Themes::~Themes()
{
    if (m_panelWrite.isActive())
        writeLayout();
}

QVariantList Themes::panels() const
{
    QVariantList list;
    for (const PanelRange &r : panelRanges) {
        const QString key = QLatin1String(r.key);
        list << QVariantMap{{QStringLiteral("key"), key},
                            {QStringLiteral("value"), m_panelSizes.value(key, r.def)},
                            {QStringLiteral("min"), r.min},
                            {QStringLiteral("max"), r.max}};
    }
    return list;
}

void Themes::setPanelSize(const QString &key, int value)
{
    const PanelRange *r = panelRange(key);
    if (!r)
        return;
    value = std::clamp(value, r->min, r->max);
    if (m_panelSizes.value(key, r->def) == value)
        return;
    m_panelSizes.insert(key, value);
    Q_EMIT panelsChanged();
    if (!m_panelWrite.isActive())
        m_panelWrite.start();
}

bool Themes::writeLayout()
{
    const QString dir = configDir();
    QDir().mkpath(dir);
    QByteArray text = m_layout.toUtf8() + '\n';
    for (auto it = m_panelSizes.cbegin(); it != m_panelSizes.cend(); ++it)
        text += it.key().toUtf8() + '=' + QByteArray::number(it.value()) + '\n';
    QSaveFile file(dir + QStringLiteral("/layout"));
    if (!file.open(QIODevice::WriteOnly) || file.write(text) < 0 || !file.commit()) {
        setError(QStringLiteral("Не удалось сохранить расположение панелей: %1").arg(file.errorString()));
        return false;
    }
    setError(QString());
    // Оболочка следит за файлом, но QSaveFile заменяет его целиком —
    // просим перечитать и явно.
    QProcess::startDetached(QStringLiteral("quickshell"),
                            {QStringLiteral("ipc"), QStringLiteral("-p"), QStringLiteral("/usr/share/sedmio/shell"), QStringLiteral("call"),
                             QStringLiteral("layout"), QStringLiteral("reload")});
    return true;
}

void Themes::rescan()
{
    // Основа для недостающих цветов — тема sedmio.
    QVariantMap base;
    for (const QString &dir : themeDirs()) {
        if (read(dir + QStringLiteral("/sedmio/theme.json"), &base))
            break;
    }

    QStringList seen;
    QVariantList themes;
    // Сначала свои (~/.local/share), они перекрывают системные.
    for (const QString &dir : themeDirs()) {
        const auto entries = QDir(dir).entryList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name);
        for (const QString &id : entries) {
            if (seen.contains(id))
                continue;
            QVariantMap values;
            if (!read(dir + QLatin1Char('/') + id + QStringLiteral("/theme.json"), &values))
                continue; // нет файла или не JSON — модуль её тоже не возьмёт
            seen << id;

            QVariantMap colors;
            for (const QString &key : previewColors) {
                const QString value = values.value(key, base.value(key)).toString();
                colors.insert(key, value.startsWith(QLatin1Char('#')) ? value : base.value(key).toString());
            }
            const QString name = values.value(QStringLiteral("name")).toString();
            themes << QVariantMap{
                {QStringLiteral("id"), id},
                {QStringLiteral("name"), name.isEmpty() ? id : name},
                {QStringLiteral("description"), values.value(QStringLiteral("description")).toString()},
                {QStringLiteral("user"), dir == themeDirs().constFirst()},
                {QStringLiteral("colors"), colors},
            };
        }
    }
    // Тема по умолчанию — первой, остальные по имени.
    std::sort(themes.begin(), themes.end(), [](const QVariant &a, const QVariant &b) {
        const QVariantMap x = a.toMap(), y = b.toMap();
        const bool xs = x.value(QStringLiteral("id")) == QLatin1String("sedmio");
        const bool ys = y.value(QStringLiteral("id")) == QLatin1String("sedmio");
        if (xs != ys)
            return xs;
        return x.value(QStringLiteral("name")).toString().localeAwareCompare(y.value(QStringLiteral("name")).toString()) < 0;
    });
    if (themes != m_themes) {
        m_themes = themes;
        Q_EMIT themesChanged();
    }

    // Следить за каталогами тем (появилась новая — в списке сразу).
    QStringList watch;
    for (const QString &dir : themeDirs()) {
        if (QDir(dir).exists())
            watch << dir;
    }
    if (!m_watcher.directories().isEmpty())
        m_watcher.removePaths(m_watcher.directories());
    if (!watch.isEmpty())
        m_watcher.addPaths(watch);
}

void Themes::choose(const QString &id)
{
    if (id.isEmpty() || id.contains(QLatin1Char('/')) || id.startsWith(QLatin1Char('.')))
        return;
    const QString dir = configDir();
    QDir().mkpath(dir);
    QSaveFile file(dir + QStringLiteral("/theme"));
    if (!file.open(QIODevice::WriteOnly) || file.write(id.toUtf8() + '\n') < 0 || !file.commit()) {
        setError(QStringLiteral("Не удалось сохранить выбор темы: %1").arg(file.errorString()));
        return;
    }
    setError(QString());
}

void Themes::chooseLayout(const QString &id)
{
    if (!layouts.contains(id) || id == m_layout)
        return;
    const QString previous = m_layout;
    m_layout = id;
    if (!writeLayout()) {
        m_layout = previous;
        return;
    }
    Q_EMIT layoutChanged();
}

void Themes::setError(const QString &error)
{
    if (error == m_error)
        return;
    m_error = error;
    Q_EMIT errorChanged();
}
