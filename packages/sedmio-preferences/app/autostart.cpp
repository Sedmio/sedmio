#include "autostart.h"

#include <KApplicationTrader>
#include <KConfigGroup>
#include <KDesktopFile>
#include <KService>

#include <QCollator>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QLocale>
#include <QProcess>
#include <QSet>
#include <QStandardPaths>

namespace
{
const QString entryGroup = QStringLiteral("Desktop Entry");

// Есть ли программа: TryExec или первое слово Exec (без env и кавычек).
bool programExists(const KDesktopFile &file)
{
    const KConfigGroup group = file.desktopGroup();
    QString program = group.readEntry("TryExec");
    if (program.isEmpty()) {
        const QStringList args = QProcess::splitCommand(group.readEntry("Exec"));
        qsizetype i = 0;
        // "env A=B prog" — пропустить env и присваивания.
        if (i < args.size() && QFileInfo(args.at(i)).fileName() == QLatin1String("env"))
            ++i;
        while (i < args.size() && args.at(i).contains(QLatin1Char('=')) && !args.at(i).startsWith(QLatin1Char('/')))
            ++i;
        if (i < args.size())
            program = args.at(i);
    }
    if (program.isEmpty())
        return true; // не знаем — не пугаем
    if (program.startsWith(QLatin1Char('/')))
        return QFileInfo(program).isExecutable();
    return !QStandardPaths::findExecutable(program).isEmpty();
}
} // namespace

Autostart::Autostart(QObject *parent)
    : QObject(parent)
    , m_entryModel(new KeyedModel(QStringLiteral("file"), this))
{
    QDir().mkpath(directory());
    m_watcher.addPath(directory());
    // Программа переписывает свою запись (Steam — при каждом запуске) —
    // перечитать, но не на каждое событие.
    m_reload.setSingleShot(true);
    m_reload.setInterval(300);
    connect(&m_reload, &QTimer::timeout, this, &Autostart::load);
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, &m_reload, qOverload<>(&QTimer::start));
    load();
}

QString Autostart::directory() const
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation) + QStringLiteral("/autostart");
}

void Autostart::load()
{
    // Записи, которые повторяют системные (/etc/xdg/autostart): это
    // пользователь или мы выключали системную службу — не программа.
    QSet<QString> systemNames;
    const QStringList configDirs = QStandardPaths::standardLocations(QStandardPaths::GenericConfigLocation);
    for (const QString &dir : configDirs) {
        if (dir == QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation))
            continue;
        for (const QString &name : QDir(dir + QStringLiteral("/autostart")).entryList({QStringLiteral("*.desktop")}, QDir::Files))
            systemNames.insert(name);
    }

    QCollator collator(QLocale(QLocale::Russian));
    collator.setCaseSensitivity(Qt::CaseInsensitive);

    struct Entry {
        QString file;
        QString name;
        QVariantMap map;
    };
    QList<Entry> entries;
    QSet<QString> present;  // id программ, что уже в автозапуске
    const QFileInfoList files = QDir(directory()).entryInfoList({QStringLiteral("*.desktop")}, QDir::Files, QDir::Name);
    for (const QFileInfo &info : files) {
        if (systemNames.contains(info.fileName()))
            continue;
        const KDesktopFile desktop(info.filePath());
        const KConfigGroup group = desktop.desktopGroup();
        if (group.readEntry("Type", QStringLiteral("Application")) != QLatin1String("Application"))
            continue;
        const bool enabled = !group.readEntry("Hidden", false) && group.readEntry("X-GNOME-Autostart-enabled", true);
        QString name = desktop.readName();
        if (name.isEmpty())
            name = info.completeBaseName();
        present.insert(info.completeBaseName());
        entries << Entry{info.filePath(), name,
                         QVariantMap{
                             {QStringLiteral("file"), info.filePath()},
                             {QStringLiteral("name"), name},
                             {QStringLiteral("icon"), desktop.readIcon().isEmpty() ? QStringLiteral("application-x-executable") : desktop.readIcon()},
                             {QStringLiteral("enabled"), enabled},
                             {QStringLiteral("missing"), !programExists(desktop)},
                         }};
    }
    std::sort(entries.begin(), entries.end(), [&collator](const Entry &a, const Entry &b) {
        return collator.compare(a.name, b.name) < 0;
    });
    m_entries.clear();
    for (const Entry &entry : std::as_const(entries))
        m_entries << entry.map;
    m_entryModel->setItems(m_entries);

    struct App {
        QString name;
        QVariantMap map;
    };
    QList<App> apps;
    const KService::List services = KApplicationTrader::query([](const KService::Ptr &service) {
        return !service->noDisplay() && !service->exec().isEmpty();
    });
    for (const KService::Ptr &service : services) {
        const QString id = service->desktopEntryName();
        if (present.contains(id) || present.contains(service->storageId().chopped(8)))
            continue;
        apps << App{service->name(),
                    QVariantMap{
                        {QStringLiteral("id"), service->storageId()},
                        {QStringLiteral("name"), service->name()},
                        {QStringLiteral("icon"), service->icon()},
                        // Где искать: название, описание, ключевые слова, имя файла.
                        {QStringLiteral("search"),
                         QStringList{service->name(), service->genericName(), service->comment(), service->keywords().join(QLatin1Char(' ')), id}
                             .join(QLatin1Char(' '))
                             .toLower()},
                    }};
    }
    std::sort(apps.begin(), apps.end(), [&collator](const App &a, const App &b) {
        return collator.compare(a.name, b.name) < 0;
    });
    m_apps.clear();
    for (const App &app : std::as_const(apps))
        m_apps << app.map;

    Q_EMIT changed();
}

void Autostart::setEnabled(const QString &file, bool enabled)
{
    if (!file.startsWith(directory() + QLatin1Char('/')) || !QFileInfo::exists(file))
        return;
    KDesktopFile desktop(file);
    KConfigGroup group = desktop.desktopGroup();
    group.writeEntry("Hidden", !enabled);
    // GNOME-овский флаг тоже: иначе запись с ним останется выключенной.
    if (group.hasKey("X-GNOME-Autostart-enabled"))
        group.writeEntry("X-GNOME-Autostart-enabled", enabled);
    if (!desktop.sync())
        m_message = QStringLiteral("Не удалось изменить: нет доступа к %1").arg(file);
    else
        m_message.clear();
    load();
}

void Autostart::remove(const QString &file)
{
    if (!file.startsWith(directory() + QLatin1Char('/')))
        return;
    m_message = QFile::remove(file) ? QString() : QStringLiteral("Не удалось убрать: нет доступа к %1").arg(file);
    load();
}

void Autostart::add(const QString &appId)
{
    const KService::Ptr service = KService::serviceByStorageId(appId);
    if (!service || service->entryPath().isEmpty())
        return;
    const QString target = directory() + QLatin1Char('/') + QFileInfo(service->entryPath()).fileName();
    QFile::remove(target);
    if (!QFile::copy(service->entryPath(), target)) {
        m_message = QStringLiteral("Не удалось добавить «%1»").arg(service->name());
        load();
        return;
    }
    // Копия системного файла может быть только для чтения.
    QFile(target).setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ReadGroup | QFileDevice::ReadOther);
    KDesktopFile desktop(target);
    KConfigGroup group = desktop.desktopGroup();
    group.deleteEntry("Hidden");
    group.deleteEntry("OnlyShowIn");
    group.deleteEntry("NotShowIn");
    if (group.hasKey("X-GNOME-Autostart-enabled"))
        group.writeEntry("X-GNOME-Autostart-enabled", true);
    desktop.sync();
    m_message.clear();
    load();
}
