#include "packages.h"

#include <QCoreApplication>
#include <QDir>
#include <QFileInfo>
#include <QPointer>
#include <QProcess>
#include <QThread>

#include <functional>
#include <memory>

#include <flatpak.h>

namespace
{
const QString pacmanLocal = QStringLiteral("/var/lib/pacman/local");
const QString pacmanSync = QStringLiteral("/var/lib/pacman/sync");

QString userFlatpakDir()
{
    return QDir::homePath() + QStringLiteral("/.local/share/flatpak");
}

// Строки вывода pacman: «имя версия» (-Q) или «репозиторий имя версия …» (-Sl).
void runPacman(QObject *context, const QStringList &args, std::function<void(const QList<QByteArray> &)> done)
{
    auto *process = new QProcess(context);
    QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
    env.insert(QStringLiteral("LC_ALL"), QStringLiteral("C"));
    process->setProcessEnvironment(env);
    QObject::connect(process, &QProcess::finished, context, [process, done](int code) {
        const QByteArray out = code == 0 ? process->readAllStandardOutput() : QByteArray();
        process->deleteLater();
        done(out.split('\n'));
    });
    QObject::connect(process, &QProcess::errorOccurred, context, [process, done](QProcess::ProcessError error) {
        if (error != QProcess::FailedToStart)
            return;
        process->deleteLater();
        done({});
    });
    process->start(QStringLiteral("pacman"), args);
}

QList<Packages::Flatpak> listInstallation(FlatpakInstallation *installation, bool user)
{
    QList<Packages::Flatpak> result;
    g_autoptr(GPtrArray) refs = flatpak_installation_list_installed_refs_by_kind(installation, FLATPAK_REF_KIND_APP, nullptr, nullptr);
    if (!refs)
        return result;
    for (guint i = 0; i < refs->len; ++i) {
        auto *ref = FLATPAK_INSTALLED_REF(g_ptr_array_index(refs, i));
        Packages::Flatpak app;
        app.id = QString::fromUtf8(flatpak_ref_get_name(FLATPAK_REF(ref)));
        app.branch = QString::fromUtf8(flatpak_ref_get_branch(FLATPAK_REF(ref)));
        app.origin = QString::fromUtf8(flatpak_installed_ref_get_origin(ref));
        app.version = QString::fromUtf8(flatpak_installed_ref_get_appdata_version(ref));
        app.name = QString::fromUtf8(flatpak_installed_ref_get_appdata_name(ref));
        app.size = qint64(flatpak_installed_ref_get_installed_size(ref));
        app.user = user;
        result << app;
    }
    return result;
}

// Обе установки: пользователя (магазин ставит сюда) и системную (если
// кто-то ставил через sudo flatpak). Вызывается в своём потоке: libflatpak
// читает с диска.
QList<Packages::Flatpak> listFlatpaks()
{
    QList<Packages::Flatpak> result;
    if (g_autoptr(FlatpakInstallation) user = flatpak_installation_new_user(nullptr, nullptr))
        result << listInstallation(user, true);
    if (g_autoptr(GPtrArray) system = flatpak_get_system_installations(nullptr, nullptr)) {
        for (guint i = 0; i < system->len; ++i)
            result << listInstallation(FLATPAK_INSTALLATION(g_ptr_array_index(system, i)), false);
    }
    return result;
}
} // namespace

Packages::Packages(QObject *parent)
    : QObject(parent)
{
    m_debounce.setSingleShot(true);
    m_debounce.setInterval(500);
    connect(&m_debounce, &QTimer::timeout, this, &Packages::refresh);
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, this, [this] {
        m_debounce.start();
        watch(); // появилась папка, которой не было, — следим и за ней
    });
    watch();
    refresh();
}

void Packages::watch()
{
    const QStringList dirs = {pacmanLocal, pacmanSync, userFlatpakDir(), userFlatpakDir() + QStringLiteral("/app"),
                              QStringLiteral("/var/lib/flatpak/app"), QDir::homePath() + QStringLiteral("/.local/share")};
    QStringList add;
    for (const QString &dir : dirs) {
        if (!m_watcher.directories().contains(dir) && QFileInfo(dir).isDir())
            add << dir;
    }
    if (!add.isEmpty())
        m_watcher.addPaths(add);
}

void Packages::refresh()
{
    readPacman();
    readFlatpak();
}

void Packages::readPacman()
{
    if (m_pacmanBusy)
        return;
    m_pacmanBusy = true;
    auto installed = std::make_shared<QHash<QString, QString>>();
    auto pending = std::make_shared<int>(2);
    auto finish = [this, installed, pending] {
        if (--*pending > 0)
            return;
        m_installed = *installed;
        m_pacmanBusy = false;
        m_pacmanReady = true;
        Q_EMIT changed();
    };
    runPacman(this, {QStringLiteral("-Q")}, [installed, finish](const QList<QByteArray> &lines) {
        for (const QByteArray &line : lines) {
            const QList<QByteArray> parts = line.split(' ');
            if (parts.size() >= 2)
                installed->insert(QString::fromUtf8(parts[0]), QString::fromUtf8(parts[1]));
        }
        finish();
    });
    runPacman(this, {QStringLiteral("-Sl")}, [this, finish](const QList<QByteArray> &lines) {
        QHash<QString, QString> sync;
        QHash<QString, QString> repo;
        for (const QByteArray &line : lines) {
            const QList<QByteArray> parts = line.split(' ');
            if (parts.size() < 3)
                continue;
            const QString name = QString::fromUtf8(parts[1]);
            if (sync.contains(name))
                continue; // pacman берёт пакет из первого репозитория в pacman.conf
            sync.insert(name, QString::fromUtf8(parts[2]));
            repo.insert(name, QString::fromUtf8(parts[0]));
        }
        m_sync = sync;
        m_repo = repo;
        finish();
    });
}

void Packages::readFlatpak()
{
    if (m_flatpakBusy)
        return;
    m_flatpakBusy = true;
    QPointer<Packages> self(this);
    QThread *thread = QThread::create([self] {
        const QList<Flatpak> list = listFlatpaks();
        QMetaObject::invokeMethod(qApp, [self, list] {
            if (!self)
                return;
            QHash<QString, Flatpak> map;
            for (const Flatpak &app : list) {
                const QString key = app.id.toLower();
                // Есть и у пользователя, и в системе — показываем пользовательскую.
                if (!map.contains(key) || app.user)
                    map.insert(key, app);
            }
            self->m_flatpaks = map;
            self->m_flatpakBusy = false;
            self->m_flatpakReady = true;
            Q_EMIT self->changed();
        });
    });
    connect(thread, &QThread::finished, thread, &QObject::deleteLater);
    thread->start(QThread::LowPriority);
}
