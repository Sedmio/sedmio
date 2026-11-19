#include "nightlight.h"

#include <KConfigGroup>
#include <KSharedConfig>

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusReply>
#include <QDateTime>
#include <QFile>
#include <QRegularExpression>
#include <QTime>
#include <QTimeZone>

// system.cpp: город пояса по-русски.
QString cityName(const QString &id);

namespace
{
const QString kwin = QStringLiteral("org.kde.KWin");
const QString path = QStringLiteral("/org/kde/KWin/NightLight");
const QString interface = QStringLiteral("org.kde.KWin.NightLight");
constexpr auto notify = KConfig::Notify | KConfig::Persistent;

KSharedConfigPtr kwinConfig()
{
    return KSharedConfig::openConfig(QStringLiteral("kwinrc"), KConfig::NoGlobals);
}

KSharedConfigPtr nightTimeConfig()
{
    return KSharedConfig::openConfig(QStringLiteral("knighttimerc"), KConfig::NoGlobals);
}

// ±DDMM или ±DDMMSS → градусы.
double coordinate(const QString &text, int degreeDigits)
{
    const double sign = text.startsWith(QLatin1Char('-')) ? -1 : 1;
    const QString digits = text.mid(1);
    const double degrees = digits.left(degreeDigits).toDouble();
    const double minutes = digits.mid(degreeDigits, 2).toDouble();
    const double seconds = digits.size() > degreeDigits + 2 ? digits.mid(degreeDigits + 2, 2).toDouble() : 0;
    return sign * (degrees + minutes / 60 + seconds / 3600);
}
} // namespace

NightLight::NightLight(QObject *parent)
    : QObject(parent)
{
    QDBusConnection::sessionBus().connect(kwin, path, QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("PropertiesChanged"), this,
                                          SLOT(readState()));
    // «Включится в 21:00» — пересчитывать, пока окно открыто.
    m_poll.setInterval(60000);
    connect(&m_poll, &QTimer::timeout, this, &NightLight::readState);
    m_poll.start();

    double latitude = 0;
    double longitude = 0;
    zoneLocation(&latitude, &longitude);
    readState();
}

NightLight::~NightLight()
{
    stopPreview();
}

bool NightLight::zoneLocation(double *latitude, double *longitude)
{
    const QString zone = QString::fromUtf8(QTimeZone::systemTimeZoneId());
    m_place.clear();
    if (zone.isEmpty())
        return false;
    for (const QString &file : {QStringLiteral("/usr/share/zoneinfo/zone1970.tab"), QStringLiteral("/usr/share/zoneinfo/zone.tab")}) {
        QFile tab(file);
        if (!tab.open(QIODevice::ReadOnly | QIODevice::Text))
            continue;
        static const QRegularExpression coords(QStringLiteral("^([+-]\\d{4,6})([+-]\\d{5,7})$"));
        while (!tab.atEnd()) {
            const QString line = QString::fromUtf8(tab.readLine());
            if (line.startsWith(QLatin1Char('#')))
                continue;
            const QStringList fields = line.split(QLatin1Char('\t'));
            if (fields.size() < 3 || fields.at(2).trimmed() != zone)
                continue;
            const auto match = coords.match(fields.at(1));
            if (!match.hasMatch())
                continue;
            *latitude = coordinate(match.captured(1), 2);
            *longitude = coordinate(match.captured(2), 3);
            m_place = cityName(zone);
            return true;
        }
    }
    return false;
}

void NightLight::readConfig()
{
    kwinConfig()->reparseConfiguration();
    nightTimeConfig()->reparseConfiguration();
    const KConfigGroup night = kwinConfig()->group(QStringLiteral("NightColor"));
    m_enabled = night.readEntry("Active", false);
    m_temperature = night.readEntry("NightTemperature", 4500);
    const QString kwinMode = night.readEntry("Mode", QStringLiteral("DarkLight"));

    const KSharedConfigPtr time = nightTimeConfig();
    const QString source = time->group(QStringLiteral("General")).readEntry("Source", QStringLiteral("Location"));
    const KConfigGroup times = time->group(QStringLiteral("Times"));
    m_evening = times.readEntry("SunsetStart", QTime(18, 0)).toString(QStringLiteral("HH:mm"));
    m_morning = times.readEntry("SunriseStart", QTime(6, 0)).toString(QStringLiteral("HH:mm"));

    if (kwinMode == QLatin1String("Constant"))
        m_mode = QStringLiteral("always");
    else if (source == QLatin1String("Times"))
        m_mode = QStringLiteral("times");
    else
        m_mode = QStringLiteral("sunset");
}

void NightLight::readState()
{
    // Настройки могли поменять и снаружи (параметры KDE, другая копия).
    readConfig();
    QDBusMessage get = QDBusMessage::createMethodCall(kwin, path, QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("GetAll"));
    get << interface;
    const QDBusReply<QVariantMap> reply = QDBusConnection::sessionBus().call(get, QDBus::Block, 2000);
    const QVariantMap props = reply.isValid() ? reply.value() : QVariantMap();
    m_available = props.value(QStringLiteral("available"), false).toBool();

    m_status.clear();
    if (m_available && m_enabled) {
        const bool day = props.value(QStringLiteral("daylight")).toBool();
        const qint64 next = props.value(QStringLiteral("scheduledTransitionDateTime")).toLongLong();
        // Секунды с начала эпохи.
        const QString at = next > 0 ? QDateTime::fromSecsSinceEpoch(next).toString(QStringLiteral("HH:mm")) : QString();
        if (m_mode == QLatin1String("always"))
            m_status = QStringLiteral("Сейчас включена");
        else if (day)
            m_status = at.isEmpty() ? QStringLiteral("Днём выключена") : QStringLiteral("Включится в %1").arg(at);
        else
            m_status = at.isEmpty() ? QStringLiteral("Сейчас включена") : QStringLiteral("Сейчас включена, выключится в %1").arg(at);
    }
    Q_EMIT changed();
}

void NightLight::setEnabled(bool enabled)
{
    KConfigGroup night = kwinConfig()->group(QStringLiteral("NightColor"));
    night.writeEntry("Active", enabled, notify);
    night.sync();
    m_enabled = enabled;
    // Закат по умолчанию KDE ищет по геолокации — закрепить пояс, как
    // обещает подпись.
    if (enabled && m_mode == QLatin1String("sunset")) {
        setMode(m_mode);
        return;
    }
    readState();
}

void NightLight::setMode(const QString &mode)
{
    KConfigGroup night = kwinConfig()->group(QStringLiteral("NightColor"));
    const KSharedConfigPtr time = nightTimeConfig();
    if (mode == QLatin1String("always")) {
        night.writeEntry("Mode", QStringLiteral("Constant"), notify);
    } else if (mode == QLatin1String("times")) {
        night.writeEntry("Mode", QStringLiteral("DarkLight"), notify);
        time->group(QStringLiteral("General")).writeEntry("Source", QStringLiteral("Times"), notify);
        KConfigGroup times = time->group(QStringLiteral("Times"));
        times.writeEntry("SunsetStart", QTime::fromString(m_evening, QStringLiteral("HH:mm")), notify);
        times.writeEntry("SunriseStart", QTime::fromString(m_morning, QStringLiteral("HH:mm")), notify);
    } else if (mode == QLatin1String("sunset")) {
        night.writeEntry("Mode", QStringLiteral("DarkLight"), notify);
        time->group(QStringLiteral("General")).writeEntry("Source", QStringLiteral("Location"), notify);
        KConfigGroup location = time->group(QStringLiteral("Location"));
        double latitude = 0;
        double longitude = 0;
        if (zoneLocation(&latitude, &longitude)) {
            location.writeEntry("Automatic", false, notify);
            location.writeEntry("Latitude", latitude, notify);
            location.writeEntry("Longitude", longitude, notify);
        } else {
            // Пояс неизвестен (UTC и т. п.) — пусть KDE определит сам.
            location.writeEntry("Automatic", true, notify);
        }
    } else {
        return;
    }
    night.sync();
    time->sync();
    readState();
}

void NightLight::setTemperature(int kelvin)
{
    KConfigGroup night = kwinConfig()->group(QStringLiteral("NightColor"));
    night.writeEntry("NightTemperature", qBound(1000, kelvin, 6500), notify);
    night.sync();
    m_temperature = qBound(1000, kelvin, 6500);
    Q_EMIT changed();
}

void NightLight::setTimes(const QString &evening, const QString &morning)
{
    const QTime eveningTime = QTime::fromString(evening, QStringLiteral("HH:mm"));
    const QTime morningTime = QTime::fromString(morning, QStringLiteral("HH:mm"));
    if (!eveningTime.isValid() || !morningTime.isValid())
        return;
    KConfigGroup times = nightTimeConfig()->group(QStringLiteral("Times"));
    times.writeEntry("SunsetStart", eveningTime, notify);
    times.writeEntry("SunriseStart", morningTime, notify);
    times.sync();
    readState();
}

void NightLight::preview(int kelvin)
{
    QDBusMessage message = QDBusMessage::createMethodCall(kwin, path, interface, QStringLiteral("preview"));
    message << uint(qBound(1000, kelvin, 6500));
    QDBusConnection::sessionBus().asyncCall(message);
    m_previewing = true;
}

void NightLight::stopPreview()
{
    if (!m_previewing)
        return;
    m_previewing = false;
    QDBusConnection::sessionBus().asyncCall(QDBusMessage::createMethodCall(kwin, path, interface, QStringLiteral("stopPreview")));
}
