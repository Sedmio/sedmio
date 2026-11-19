#include "tasks.h"

#include <KApplicationTrader>
#include <KService>
#include <KWindowSystem>

#include <QCollator>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDateTime>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QLocale>
#include <QRegularExpression>
#include <QThread>

#include <unistd.h>

namespace
{
const QString systemdService = QStringLiteral("org.freedesktop.systemd1");
const QString systemdPath = QStringLiteral("/org/freedesktop/systemd1");
const QString systemdManager = QStringLiteral("org.freedesktop.systemd1.Manager");
const QString shellUnit = QStringLiteral("sedmio-shell.service");
constexpr qint64 hungAfterMs = 5000;

QByteArray readFile(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
        return {};
    return file.readAll();
}

// «key value» построчно (cpu.stat, memory.stat, /proc/meminfo).
quint64 field(const QByteArray &text, const QByteArray &key)
{
    for (const QByteArray &line : text.split('\n')) {
        if (!line.startsWith(key))
            continue;
        if (line.size() == key.size() || (line.at(key.size()) != ' ' && line.at(key.size()) != ':'))
            continue;
        const QByteArray rest = line.mid(key.size() + 1).simplified();
        return rest.left(rest.indexOf(' ') < 0 ? rest.size() : rest.indexOf(' ')).toULongLong();
    }
    return 0;
}

bool populated(const QString &path)
{
    return field(readFile(path + QStringLiteral("/cgroup.events")), "populated") != 0;
}

// Процессы группы со всеми вложенными (Konsole кладёт вкладки в свои).
QList<int> processes(const QString &path)
{
    QList<int> pids;
    const auto add = [&pids](const QString &dir) {
        for (const QByteArray &line : readFile(dir + QStringLiteral("/cgroup.procs")).split('\n'))
            if (!line.isEmpty())
                pids << line.toInt();
    };
    add(path);
    QDirIterator it(path, QDir::Dirs | QDir::NoDotAndDotDot, QDirIterator::Subdirectories);
    while (it.hasNext())
        add(it.next());
    return pids;
}

// Своя память программы: без файлового кэша (его ядро отдаст само),
// но с общей памятью (буферы окон и т. п.).
qint64 memoryOf(const QString &path)
{
    const QByteArray stat = readFile(path + QStringLiteral("/memory.stat"));
    if (stat.isEmpty())
        return readFile(path + QStringLiteral("/memory.current")).trimmed().toLongLong();
    return qint64(field(stat, "anon") + field(stat, "shmem") + field(stat, "kernel"));
}

// \x2d → «-» (так systemd экранирует имена).
QString unescape(const QString &text)
{
    QString out;
    for (int i = 0; i < text.size(); ++i) {
        if (text.at(i) == QLatin1Char('\\') && i + 3 < text.size() && text.at(i + 1) == QLatin1Char('x')) {
            bool ok = false;
            const int code = text.mid(i + 2, 2).toInt(&ok, 16);
            if (ok) {
                out += QChar(code);
                i += 3;
                continue;
            }
        }
        out += text.at(i);
    }
    return out;
}

// app-<id>-<случайное>.scope / app-<id>@<случайное>.service → id.
QString appIdOf(const QString &unit)
{
    QString rest = unit.mid(4);
    if (rest.endsWith(QLatin1String(".scope"))) {
        rest.chop(6);
        const int dash = rest.lastIndexOf(QLatin1Char('-'));
        if (dash > 0)
            rest.truncate(dash);
    } else if (rest.endsWith(QLatin1String(".service"))) {
        rest.chop(8);
        const int at = rest.indexOf(QLatin1Char('@'));
        if (at > 0)
            rest.truncate(at);
    }
    return unescape(rest);
}

// Имя программы процесса: argv[0] без пути (comm обрезан до 15 букв);
// у скрипта (sh x, python3 x) — имя скрипта.
QString comm(int pid)
{
    const QList<QByteArray> args = readFile(QStringLiteral("/proc/%1/cmdline").arg(pid)).split('\0');
    QString first = args.isEmpty() ? QString() : QFileInfo(QString::fromUtf8(args.constFirst())).fileName();
    static const QRegularExpression interpreter(QStringLiteral("^(sh|bash|dash|zsh|python[0-9.]*|perl|ruby|node|gjs)$"));
    if (interpreter.match(first).hasMatch() && args.size() > 1 && !args.at(1).isEmpty() && !args.at(1).startsWith('-'))
        first = QFileInfo(QString::fromUtf8(args.at(1))).fileName();
    return first.isEmpty() ? QString::fromUtf8(readFile(QStringLiteral("/proc/%1/comm").arg(pid)).trimmed()) : first;
}

struct SystemPart {
    const char *key;
    const char *name;
    const char *icon;
};

// Части системы по имени юнита.
SystemPart systemPart(const QString &unit)
{
    if (unit == shellUnit)
        return {"shell", "Оболочка Sedmio", "user-desktop"};
    if (unit.startsWith(QLatin1String("plasma-kwin")))
        return {"kwin", "Окна и экраны (KWin)", "preferences-system-windows"};
    if (unit.startsWith(QLatin1String("pipewire")) || unit.startsWith(QLatin1String("wireplumber")))
        return {"sound", "Звук (PipeWire)", "audio-card"};
    if (unit.startsWith(QLatin1String("xdg-")))
        return {"portals", "Порталы (выбор файлов и т. п.)", "folder-open"};
    if (unit.startsWith(QLatin1String("sedmio-")))
        return {"sedmio", "Службы Sedmio", "preferences-system"};
    if (unit.startsWith(QLatin1String("plasma-")) || unit.startsWith(QLatin1String("kde")))
        return {"kde", "Службы KDE", "kde"};
    return {"other", "Прочие службы", "preferences-other"};
}
} // namespace

Tasks::Tasks(QObject *parent)
    : QObject(parent)
{
    // Своя группа: 0::/user.slice/user-1000.slice/user@1000.service/app.slice/…
    const QString own = QString::fromUtf8(readFile(QStringLiteral("/proc/self/cgroup")));
    static const QRegularExpression userManager(QStringLiteral("0::(/user\\.slice/[^\\n]*?/user@\\d+\\.service)"));
    const auto match = userManager.match(own);
    QString root = match.hasMatch() ? QStringLiteral("/sys/fs/cgroup") + match.captured(1)
                                    : QStringLiteral("/sys/fs/cgroup/user.slice/user-%1.slice/user@%1.service").arg(getuid());
    if (QFileInfo(root + QStringLiteral("/app.slice")).isDir())
        m_root = root;

    m_timer.setInterval(2000);
    connect(&m_timer, &QTimer::timeout, this, &Tasks::refresh);
    m_clock.start();
    refresh();
}

void Tasks::setRunning(bool running)
{
    if (running == m_timer.isActive())
        return;
    if (running) {
        refresh();
        m_timer.start();
    } else {
        m_timer.stop();
    }
    Q_EMIT runningChanged();
}

QString Tasks::formatBytes(qint64 bytes)
{
    const QLocale locale(QLocale::Russian);
    const double mb = bytes / 1048576.0;
    if (mb < 1)
        return QStringLiteral("< 1 МБ");
    if (mb < 1000)
        return QStringLiteral("%1 МБ").arg(qRound(mb));
    return QStringLiteral("%1 ГБ").arg(locale.toString(mb / 1024, 'f', 1));
}

QString Tasks::memoryText() const
{
    if (m_memoryTotal <= 0)
        return {};
    const QLocale locale(QLocale::Russian);
    return QStringLiteral("%1 из %2 ГБ")
        .arg(locale.toString(m_memoryUsed / 1073741824.0, 'f', 1), locale.toString(m_memoryTotal / 1073741824.0, 'f', 1));
}

void Tasks::identify(Group &group, const QString &unit, const QString &path) const
{
    // Ищем .desktop: по id, затем без префикса запускающего (app-flatpak-…),
    // затем по имени исполняемого файла.
    QString id = unit.startsWith(QLatin1String("app-")) ? appIdOf(unit) : QString();
    const QList<int> pids = processes(path);
    const QString first = pids.isEmpty() ? QString() : comm(pids.constFirst());
    if (id.isEmpty())
        id = first;

    auto cached = m_names.constFind(id);
    if (cached != m_names.constEnd()) {
        group.key = id;
        group.name = cached->first;
        group.icon = cached->second;
        return;
    }

    QStringList candidates{id};
    const int dash = id.indexOf(QLatin1Char('-'));
    if (dash > 0)
        candidates << id.mid(dash + 1);
    KService::Ptr service;
    for (const QString &candidate : std::as_const(candidates)) {
        service = KService::serviceByDesktopName(candidate);
        if (!service)
            service = KService::serviceByStorageId(candidate);
        if (service)
            break;
    }
    if (!service && !first.isEmpty()) {
        const KService::List found = KApplicationTrader::query([&first](const KService::Ptr &s) {
            const QString exec = s->exec().section(QLatin1Char(' '), 0, 0);
            return QFileInfo(exec).fileName() == first;
        });
        if (!found.isEmpty())
            service = found.constFirst();
    }
    group.key = id;
    // Без .desktop: id группы, если запустили мы (app-<id>-…), иначе имя процесса.
    group.name = service ? service->name() : (unit.startsWith(QLatin1String("app-")) || first.isEmpty() ? id : first);
    group.icon = service && !service->icon().isEmpty() ? service->icon() : QStringLiteral("application-x-executable");
    const_cast<Tasks *>(this)->m_names.insert(id, {group.name, group.icon});
}

double Tasks::unitCpu(const QString &path, quint64 elapsedUs)
{
    const quint64 usage = field(readFile(path + QStringLiteral("/cpu.stat")), "usage_usec");
    const auto previous = m_cpuUsage.constFind(path);
    double percent = 0;
    if (previous != m_cpuUsage.constEnd() && elapsedUs > 0 && usage >= *previous)
        percent = 100.0 * double(usage - *previous) / double(elapsedUs) / qMax(1, QThread::idealThreadCount());
    m_cpuUsage.insert(path, usage);
    return percent;
}

void Tasks::addUnit(const QString &unit, const QString &path, const QString &slice)
{
    if (!populated(path))
        return;
    const quint64 elapsedUs = m_lastScan ? (m_clock.nsecsElapsed() / 1000 - m_lastScan) : 0;
    const qint64 memory = memoryOf(path);
    const double cpu = unitCpu(path, elapsedUs);

    // Программа — группа app-… в app.slice (кроме запущенного по D-Bus:
    // это помощники вроде at-spi) или запущенное через systemd-run.
    const bool program = slice == QLatin1String("app.slice")
        && ((unit.startsWith(QLatin1String("app-")) && !unit.startsWith(QLatin1String("app-dbus")))
            || unit.startsWith(QLatin1String("run-")));

    Group probe;
    QHash<QString, Group> *target = nullptr;
    if (program) {
        identify(probe, unit, path);
        target = &m_appGroups;
    } else {
        const SystemPart part = systemPart(unit);
        probe.key = QString::fromLatin1(part.key);
        probe.name = QString::fromUtf8(part.name);
        probe.icon = QString::fromLatin1(part.icon);
        target = &m_systemGroups;
    }
    Group &group = (*target)[probe.key];
    if (group.key.isEmpty()) {
        group.key = probe.key;
        group.name = probe.name;
        group.icon = probe.icon;
        group.order = target->size();
    }
    group.units << Unit{unit, path};
    group.memory += memory;
    group.cpu += cpu;
    group.processes += processes(path).size();
}

void Tasks::scanDirectory(const QString &dir, const QString &slice)
{
    const QFileInfoList entries = QDir(dir).entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot);
    for (const QFileInfo &entry : entries) {
        const QString name = entry.fileName();
        if (name.endsWith(QLatin1String(".slice"))) {
            // Вложенный срез (app-dbus-…slice и т. п.) — его юниты.
            for (const QFileInfo &inner : QDir(entry.filePath()).entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot))
                if (inner.fileName().endsWith(QLatin1String(".service")) || inner.fileName().endsWith(QLatin1String(".scope")))
                    addUnit(name.startsWith(QLatin1String("app-dbus")) ? name : inner.fileName(), inner.filePath(), slice);
        } else if (name.endsWith(QLatin1String(".service")) || name.endsWith(QLatin1String(".scope"))) {
            addUnit(name, entry.filePath(), slice);
        }
    }
}

void Tasks::readTotals(quint64 elapsedUs)
{
    Q_UNUSED(elapsedUs)
    const QByteArray stat = readFile(QStringLiteral("/proc/stat"));
    const QList<QByteArray> cpu = stat.left(stat.indexOf('\n')).simplified().split(' ');
    if (cpu.size() > 8 && cpu.constFirst() == "cpu") {
        quint64 total = 0;
        for (int i = 1; i < cpu.size(); ++i)
            total += cpu.at(i).toULongLong();
        // guest уже входит в user — не считать дважды.
        if (cpu.size() > 10)
            total -= cpu.at(9).toULongLong() + cpu.at(10).toULongLong();
        const quint64 idle = cpu.at(4).toULongLong() + cpu.at(5).toULongLong();
        const quint64 busy = total - idle;
        if (m_lastCpuTotal && total > m_lastCpuTotal)
            m_cpu = 100.0 * double(busy - m_lastCpuBusy) / double(total - m_lastCpuTotal);
        m_lastCpuBusy = busy;
        m_lastCpuTotal = total;
    }
    const QByteArray meminfo = readFile(QStringLiteral("/proc/meminfo"));
    m_memoryTotal = qint64(field(meminfo, "MemTotal")) * 1024;
    m_memoryUsed = m_memoryTotal - qint64(field(meminfo, "MemAvailable")) * 1024;
}

void Tasks::refresh()
{
    const quint64 nowUs = m_clock.nsecsElapsed() / 1000;
    readTotals(m_lastScan ? nowUs - m_lastScan : 0);

    m_appGroups.clear();
    m_systemGroups.clear();
    if (!m_root.isEmpty()) {
        scanDirectory(m_root + QStringLiteral("/app.slice"), QStringLiteral("app.slice"));
        scanDirectory(m_root + QStringLiteral("/session.slice"), QStringLiteral("session.slice"));
        scanDirectory(m_root + QStringLiteral("/background.slice"), QStringLiteral("background.slice"));
    }
    m_lastScan = nowUs;

    // Пропавшие пути — забыть их счётчики.
    QSet<QString> alive;
    for (const auto *groups : {&m_appGroups, &m_systemGroups})
        for (const Group &group : *groups)
            for (const Unit &unit : group.units)
                alive.insert(unit.path);
    for (auto it = m_cpuUsage.begin(); it != m_cpuUsage.end();)
        it = alive.contains(it.key()) ? std::next(it) : m_cpuUsage.erase(it);

    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    for (auto it = m_ending.begin(); it != m_ending.end();)
        it = m_appGroups.contains(it.key()) ? std::next(it) : m_ending.erase(it);

    QCollator collator(QLocale(QLocale::Russian));
    collator.setCaseSensitivity(Qt::CaseInsensitive);
    QList<Group> apps = m_appGroups.values();
    std::sort(apps.begin(), apps.end(), [&collator](const Group &a, const Group &b) {
        return collator.compare(a.name, b.name) < 0;
    });
    m_apps.clear();
    for (const Group &group : std::as_const(apps)) {
        const auto ending = m_ending.constFind(group.key);
        m_apps << QVariantMap{
            {QStringLiteral("key"), group.key},
            {QStringLiteral("name"), group.name},
            {QStringLiteral("icon"), group.icon},
            {QStringLiteral("cpu"), group.cpu},
            {QStringLiteral("memory"), group.memory},
            {QStringLiteral("memoryText"), formatBytes(group.memory)},
            {QStringLiteral("processes"), group.processes},
            {QStringLiteral("ending"), ending != m_ending.constEnd()},
            {QStringLiteral("hung"), ending != m_ending.constEnd() && now - *ending > hungAfterMs},
        };
    }

    QList<Group> system = m_systemGroups.values();
    static const QStringList order{QStringLiteral("shell"), QStringLiteral("kwin"), QStringLiteral("sound"), QStringLiteral("portals"),
                                   QStringLiteral("sedmio"), QStringLiteral("kde"), QStringLiteral("other")};
    std::sort(system.begin(), system.end(), [](const Group &a, const Group &b) {
        return order.indexOf(a.key) < order.indexOf(b.key);
    });
    m_system.clear();
    for (const Group &group : std::as_const(system)) {
        m_system << QVariantMap{
            {QStringLiteral("key"), group.key},
            {QStringLiteral("name"), group.name},
            {QStringLiteral("icon"), group.icon},
            {QStringLiteral("cpu"), group.cpu},
            {QStringLiteral("memory"), group.memory},
            {QStringLiteral("memoryText"), formatBytes(group.memory)},
            {QStringLiteral("restartable"), group.key == QLatin1String("shell")},
            {QStringLiteral("stopped"), false},
        };
    }
    // Оболочка упала — панели нет, и как раз тогда открывают диспетчер
    // (Ctrl+Shift+Esc ловит KWin, не оболочка): дать её запустить.
    if (!m_systemGroups.contains(QStringLiteral("shell"))) {
        const SystemPart part = systemPart(shellUnit);
        m_system.prepend(QVariantMap{
            {QStringLiteral("key"), QStringLiteral("shell")},
            {QStringLiteral("name"), QString::fromUtf8(part.name)},
            {QStringLiteral("icon"), QString::fromLatin1(part.icon)},
            {QStringLiteral("cpu"), 0.0},
            {QStringLiteral("memory"), 0},
            {QStringLiteral("memoryText"), QString()},
            {QStringLiteral("restartable"), true},
            {QStringLiteral("stopped"), true},
        });
    }
    Q_EMIT changed();
}

void Tasks::callSystemd(const QString &method, const QVariantList &args)
{
    QDBusMessage message = QDBusMessage::createMethodCall(systemdService, systemdPath, systemdManager, method);
    message.setArguments(args);
    auto *watcher = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(message, 10000), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, watcher] {
        watcher->deleteLater();
        if (watcher->isError()) {
            m_message = QStringLiteral("Не получилось: %1").arg(watcher->error().message());
            Q_EMIT changed();
        }
        QTimer::singleShot(300, this, &Tasks::refresh);
    });
}

void Tasks::end(const QString &key)
{
    const auto group = m_appGroups.constFind(key);
    if (group == m_appGroups.constEnd())
        return;
    m_message.clear();
    m_ending.insert(key, QDateTime::currentMSecsSinceEpoch());
    for (const Unit &unit : group->units)
        callSystemd(QStringLiteral("StopUnit"), {unit.name, QStringLiteral("replace")});
    refresh();
    // Через 5 с — показать «не отвечает», если ещё жив.
    QTimer::singleShot(hungAfterMs + 100, this, &Tasks::refresh);
}

void Tasks::forceEnd(const QString &key)
{
    const auto group = m_appGroups.constFind(key);
    if (group == m_appGroups.constEnd())
        return;
    m_message.clear();
    for (const Unit &unit : group->units)
        callSystemd(QStringLiteral("KillUnit"), {unit.name, QStringLiteral("all"), 9});
}

void Tasks::restartShell()
{
    m_message.clear();
    // После нескольких падений подряд systemd больше не запускает её сам
    // (start limit) — сбрасываем, иначе и RestartUnit откажет.
    callSystemd(QStringLiteral("ResetFailedUnit"), {shellUnit});
    callSystemd(QStringLiteral("RestartUnit"), {shellUnit, QStringLiteral("replace")});
}

// ---- Одно окно на сеанс.

namespace
{
const QString tasksService = QStringLiteral("org.sedmio.Tasks");
const QString tasksPath = QStringLiteral("/org/sedmio/Tasks");
}

TasksHost::TasksHost(QObject *parent)
    : QObject(parent)
{
}

bool TasksHost::registerOnBus()
{
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.isConnected())
        return true;
    if (!bus.registerService(tasksService))
        return false;
    new TasksAdaptor(this);
    bus.registerObject(tasksPath, this);
    return true;
}

bool TasksHost::forward()
{
    QDBusMessage message = QDBusMessage::createMethodCall(tasksService, tasksPath, tasksService, QStringLiteral("Show"));
    message << qEnvironmentVariable("XDG_ACTIVATION_TOKEN");
    const QDBusMessage reply = QDBusConnection::sessionBus().call(message, QDBus::Block, 3000);
    return reply.type() == QDBusMessage::ReplyMessage;
}

void TasksHost::show(const QString &token)
{
    if (!m_window)
        return;
    m_window->show();
    if (m_window->windowState() & Qt::WindowMinimized)
        m_window->showNormal();
    if (!token.isEmpty())
        KWindowSystem::setCurrentXdgActivationToken(token);
    KWindowSystem::activateWindow(m_window);
}
