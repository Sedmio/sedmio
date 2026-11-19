#include "system.h"

#include <KFormat>

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusVariant>
#include <QDateTime>
#include <QFile>
#include <QLocale>
#include <QOffscreenSurface>
#include <QOpenGLContext>
#include <QOpenGLFunctions>
#include <QProcess>
#include <QRegularExpression>
#include <QStorageInfo>
#include <QSysInfo>
#include <QTimeZone>

#include <unicode/locid.h>
#include <unicode/timezone.h>
#include <unicode/tznames.h>

#include <algorithm>
#include <memory>

namespace
{
const QString timedService = QStringLiteral("org.freedesktop.timedate1");
const QString timedPath = QStringLiteral("/org/freedesktop/timedate1");
const QString hostService = QStringLiteral("org.freedesktop.hostname1");
const QString hostPath = QStringLiteral("/org/freedesktop/hostname1");
const QString propertiesInterface = QStringLiteral("org.freedesktop.DBus.Properties");

QDBusConnection bus()
{
    return QDBusConnection::systemBus();
}

QVariantMap allProperties(const QString &service, const QString &path)
{
    auto message = QDBusMessage::createMethodCall(service, path, propertiesInterface, QStringLiteral("GetAll"));
    message << service; // интерфейс называется так же, как служба
    const QDBusMessage reply = bus().call(message, QDBus::Block, 3000);
    if (reply.type() != QDBusMessage::ReplyMessage || reply.arguments().isEmpty())
        return {};
    return qdbus_cast<QVariantMap>(reply.arguments().constFirst());
}

QString readFile(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
        return {};
    return QString::fromUtf8(file.readAll());
}

QString offsetLabel(int seconds)
{
    const int minutes = qAbs(seconds) / 60;
    return QStringLiteral("UTC%1%2:%3")
        .arg(seconds < 0 ? QLatin1Char('-') : QLatin1Char('+'))
        .arg(minutes / 60, 2, 10, QLatin1Char('0'))
        .arg(minutes % 60, 2, 10, QLatin1Char('0'));
}

// Ошибка polkit «отменено» — пользователь сам закрыл окно пароля.
bool canceled(const QDBusError &error)
{
    return error.name().contains(QLatin1String("Interactive")) || error.name().endsWith(QLatin1String(".Cancelled"))
        || error.message().contains(QLatin1String("cancel"), Qt::CaseInsensitive);
}
} // namespace

// Город пояса по-русски («Бангкок», «Москва») — из ICU; нет перевода —
// из самого имени пояса.
QString cityName(const QString &id)
{
    static const std::unique_ptr<icu::TimeZoneNames> names = [] {
        UErrorCode status = U_ZERO_ERROR;
        std::unique_ptr<icu::TimeZoneNames> created(icu::TimeZoneNames::createInstance(icu::Locale("ru"), status));
        if (U_FAILURE(status))
            created.reset();
        return created;
    }();
    if (names) {
        icu::UnicodeString city;
        names->getExemplarLocationName(icu::UnicodeString(reinterpret_cast<const UChar *>(id.utf16()), int32_t(id.size())), city);
        if (!city.isEmpty())
            return QString(reinterpret_cast<const QChar *>(city.getBuffer()), city.length());
    }
    return id.section(QLatin1Char('/'), -1).replace(QLatin1Char('_'), QLatin1Char(' '));
}

QString timeZoneLabel(const QString &id)
{
    const QTimeZone zone(id.toUtf8());
    if (!zone.isValid())
        return id;
    const QDateTime now = QDateTime::currentDateTime();
    const QString city = cityName(id);
    const QString name = zone.displayName(QTimeZone::StandardTime, QTimeZone::LongName, QLocale(QLocale::Russian));
    return QStringLiteral("%1 — %2 (%3)").arg(city, name, offsetLabel(zone.offsetFromUtc(now)));
}

SystemInfo::SystemInfo(QObject *parent)
    : QObject(parent)
{
    load();
    for (const auto &[service, path] : {std::pair{timedService, timedPath}, std::pair{hostService, hostPath}}) {
        bus().connect(service, path, propertiesInterface, QStringLiteral("PropertiesChanged"), this,
                      SLOT(onPropertiesChanged(QString, QVariantMap, QStringList)));
    }
}

void SystemInfo::load()
{
    const QVariantMap timed = allProperties(timedService, timedPath);
    m_timeZone = timed.value(QStringLiteral("Timezone")).toString();
    m_ntp = timed.value(QStringLiteral("NTP")).toBool();
    m_canNtp = timed.value(QStringLiteral("CanNTP")).toBool();
    const QVariantMap host = allProperties(hostService, hostPath);
    m_hostname = host.value(QStringLiteral("StaticHostname")).toString();
    if (m_hostname.isEmpty())
        m_hostname = QSysInfo::machineHostName();
    if (m_timeZone.isEmpty())
        m_timeZone = QString::fromUtf8(QTimeZone::systemTimeZoneId());
    Q_EMIT changed();
}

void SystemInfo::onPropertiesChanged(const QString &, const QVariantMap &, const QStringList &)
{
    load();
}

QString SystemInfo::timeZoneLabel() const
{
    return ::timeZoneLabel(m_timeZone);
}

QString SystemInfo::timeText(const QDateTime &moment) const
{
    const QTimeZone zone(m_timeZone.toUtf8());
    return QLocale(QLocale::Russian).toString(zone.isValid() ? moment.toTimeZone(zone) : moment, QStringLiteral("HH:mm:ss"));
}

QString SystemInfo::dateText(const QDateTime &moment) const
{
    const QTimeZone zone(m_timeZone.toUtf8());
    return QLocale(QLocale::Russian).toString(zone.isValid() ? moment.toTimeZone(zone) : moment, QStringLiteral("dddd, d MMMM yyyy"));
}

QVariantList SystemInfo::timeZones() const
{
    struct Zone {
        QString id;
        int offset;
    };
    QList<Zone> zones;
    const QDateTime now = QDateTime::currentDateTime();
    static const QRegularExpression regional(QStringLiteral("^(Africa|America|Antarctica|Asia|Atlantic|Australia|Europe|Indian|Pacific)/"));
    for (const QByteArray &raw : QTimeZone::availableTimeZoneIds()) {
        const QString id = QString::fromUtf8(raw);
        if (!regional.match(id).hasMatch())
            continue;
        // Старые имена-псевдонимы (America/Atka = America/Adak) — только
        // путают: оставляем основные.
        icu::UnicodeString canonical;
        UBool system = false;
        UErrorCode status = U_ZERO_ERROR;
        icu::TimeZone::getCanonicalID(icu::UnicodeString(reinterpret_cast<const UChar *>(id.utf16()), int32_t(id.size())),
                                      canonical, system, status);
        if (U_SUCCESS(status) && canonical != icu::UnicodeString(reinterpret_cast<const UChar *>(id.utf16()), int32_t(id.size())))
            continue;
        zones.append({id, QTimeZone(raw).offsetFromUtc(now)});
    }
    std::sort(zones.begin(), zones.end(), [](const Zone &a, const Zone &b) {
        return a.offset < b.offset || (a.offset == b.offset && a.id < b.id);
    });

    QVariantList list;
    for (const auto &zone : zones) {
        const QString label = ::timeZoneLabel(zone.id);
        list.append(QVariantMap{{QStringLiteral("id"), zone.id},
                                {QStringLiteral("label"), label},
                                {QStringLiteral("search"), (label + QLatin1Char(' ') + zone.id).toLower()}});
    }
    return list;
}

void SystemInfo::call(const QString &service, const QString &path, const QString &interface, const QString &method,
                      const QVariantList &args, std::function<void()> done)
{
    auto message = QDBusMessage::createMethodCall(service, path, interface, method);
    message.setArguments(args);
    message.setInteractiveAuthorizationAllowed(true);
    auto *watcher = new QDBusPendingCallWatcher(bus().asyncCall(message, 120000), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, done](QDBusPendingCallWatcher *w) {
        w->deleteLater();
        const QDBusPendingReply<> reply = *w;
        if (!reply.isError() && done)
            done();
        m_error = reply.isError() && !canceled(reply.error())
            ? QStringLiteral("Не получилось: %1").arg(reply.error().message())
            : QString();
        load();
    });
}

void SystemInfo::setTimeZone(const QString &id)
{
    if (id == m_timeZone)
        return;
    // Процессы запоминают пояс при запуске (libc читает /etc/localtime
    // один раз), и часы оболочки остались бы в старом. Пояс меняют редко —
    // перезапускаем оболочку, панель на секунду мигнёт.
    call(timedService, timedPath, timedService, QStringLiteral("SetTimezone"), {id, true}, [] {
        QProcess::startDetached(QStringLiteral("systemctl"),
                                {QStringLiteral("--user"), QStringLiteral("try-restart"), QStringLiteral("sedmio-shell.service")});
    });
}

void SystemInfo::setNtp(bool enabled)
{
    call(timedService, timedPath, timedService, QStringLiteral("SetNTP"), {enabled, true});
}

bool SystemInfo::validHostname(const QString &name) const
{
    static const QRegularExpression valid(QStringLiteral("^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$"));
    return valid.match(name).hasMatch();
}

void SystemInfo::setHostname(const QString &name)
{
    if (!validHostname(name) || name == m_hostname)
        return;
    call(hostService, hostPath, hostService, QStringLiteral("SetStaticHostname"), {name, true});
}

QString SystemInfo::osName() const
{
    const QString release = readFile(QStringLiteral("/etc/os-release"));
    static const QRegularExpression pretty(QStringLiteral("^PRETTY_NAME=\"?([^\"\\n]*)"), QRegularExpression::MultilineOption);
    const auto match = pretty.match(release);
    return match.hasMatch() ? match.captured(1) : QSysInfo::prettyProductName();
}

QString SystemInfo::kernel() const
{
    return QStringLiteral("Linux %1").arg(QSysInfo::kernelVersion());
}

QString SystemInfo::cpu() const
{
    const QString info = readFile(QStringLiteral("/proc/cpuinfo"));
    static const QRegularExpression model(QStringLiteral("^model name\\s*:\\s*(.*)$"), QRegularExpression::MultilineOption);
    const auto match = model.match(info);
    QString name = match.hasMatch() ? match.captured(1).trimmed() : QSysInfo::currentCpuArchitecture();
    // «AMD Ryzen 7 7700 8-Core Processor» — без лишнего хвоста.
    name.remove(QRegularExpression(QStringLiteral("\\s+\\d+-Core Processor$")));
    const int threads = info.count(QRegularExpression(QStringLiteral("^processor\\s*:"), QRegularExpression::MultilineOption));
    if (threads <= 0)
        return name;
    const int mod10 = threads % 10, mod100 = threads % 100;
    const char *word = mod10 == 1 && mod100 != 11 ? "поток"
        : mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14) ? "потока" : "потоков";
    return QStringLiteral("%1 · %2 %3").arg(name).arg(threads).arg(QString::fromUtf8(word));
}

QString SystemInfo::memory() const
{
    const QString info = readFile(QStringLiteral("/proc/meminfo"));
    static const QRegularExpression total(QStringLiteral("^MemTotal:\\s*(\\d+) kB"), QRegularExpression::MultilineOption);
    const auto match = total.match(info);
    if (!match.hasMatch())
        return {};
    return KFormat().formatByteSize(match.captured(1).toDouble() * 1024, 1, KFormat::IECBinaryDialect);
}

QString SystemInfo::gpu() const
{
    // Видеокарта, на которой рисует сам этот процесс: строка OpenGL.
    QOpenGLContext context;
    if (!context.create())
        return {};
    QOffscreenSurface surface;
    surface.setFormat(context.format());
    surface.create();
    if (!context.makeCurrent(&surface))
        return {};
    QString renderer = QString::fromUtf8(reinterpret_cast<const char *>(context.functions()->glGetString(GL_RENDERER)));
    context.doneCurrent();
    // «NVIDIA GeForce RTX 4060/PCIe/SSE2», «AMD Radeon Graphics (radeonsi, …)».
    renderer = renderer.section(QLatin1Char('/'), 0, 0);
    renderer.remove(QRegularExpression(QStringLiteral("\\s*\\(.*\\)$")));
    return renderer.trimmed();
}

QString SystemInfo::disk() const
{
    const QStorageInfo root = QStorageInfo::root();
    if (!root.isValid())
        return {};
    KFormat format;
    return QStringLiteral("%1 свободно из %2")
        .arg(format.formatByteSize(root.bytesAvailable(), 0, KFormat::MetricBinaryDialect),
             format.formatByteSize(root.bytesTotal(), 0, KFormat::MetricBinaryDialect));
}
