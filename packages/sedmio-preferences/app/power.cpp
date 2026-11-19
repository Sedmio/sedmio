#include "power.h"

#include <KConfig>
#include <KConfigGroup>

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusVariant>

namespace
{
const QString pmService = QStringLiteral("org.kde.Solid.PowerManagement");
const QString pmPath = QStringLiteral("/org/kde/Solid/PowerManagement");

// Значения PowerDevil::PowerButtonAction.
constexpr uint NoAction = 0;
constexpr uint Sleep = 1;
constexpr uint TurnOffScreen = 64;
constexpr uint PromptLogoutDialog = 16;

const QStringList allProfiles = {QStringLiteral("AC"), QStringLiteral("Battery"), QStringLiteral("LowBattery")};

QVariant systemProperty(const QString &service, const QString &path, const QString &interface, const QString &name)
{
    auto message = QDBusMessage::createMethodCall(service, path, QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("Get"));
    message << interface << name;
    const QDBusMessage reply = QDBusConnection::systemBus().call(message, QDBus::Block, 2000);
    if (reply.type() != QDBusMessage::ReplyMessage || reply.arguments().isEmpty())
        return {};
    return reply.arguments().constFirst().value<QDBusVariant>().variant();
}

// Значения по умолчанию — как у powerdevil (powerdevilsettingsdefaults.cpp,
// не мобильное устройство): если ключа в powerdevilrc нет, действует это.
int pick(const QString &profile, int ac, int battery, int low)
{
    return profile == QLatin1String("Battery") ? battery : profile == QLatin1String("LowBattery") ? low : ac;
}
} // namespace

Power::Power(QObject *parent)
    : QObject(parent)
{
    m_isVM = !systemProperty(QStringLiteral("org.freedesktop.systemd1"), QStringLiteral("/org/freedesktop/systemd1"),
                             QStringLiteral("org.freedesktop.systemd1.Manager"), QStringLiteral("Virtualization"))
                  .toString()
                  .isEmpty();

    auto canSuspend = QDBusMessage::createMethodCall(QStringLiteral("org.freedesktop.login1"), QStringLiteral("/org/freedesktop/login1"),
                                                     QStringLiteral("org.freedesktop.login1.Manager"), QStringLiteral("CanSuspend"));
    const QDBusMessage reply = QDBusConnection::systemBus().call(canSuspend, QDBus::Block, 2000);
    if (reply.type() == QDBusMessage::ReplyMessage && !reply.arguments().isEmpty()) {
        const QString answer = reply.arguments().constFirst().toString();
        m_canSuspend = answer == QLatin1String("yes") || answer == QLatin1String("challenge");
    }

    const QString upower = QStringLiteral("org.freedesktop.UPower");
    m_lidPresent = systemProperty(upower, QStringLiteral("/org/freedesktop/UPower"), upower, QStringLiteral("LidIsPresent")).toBool();
    const QString display = QStringLiteral("/org/freedesktop/UPower/devices/DisplayDevice");
    const QString device = QStringLiteral("org.freedesktop.UPower.Device");
    m_hasBattery = systemProperty(upower, display, device, QStringLiteral("IsPresent")).toBool()
        && systemProperty(upower, display, device, QStringLiteral("Type")).toUInt() == 2;

    load();
}

void Power::load()
{
    // Каждый раз заново: файл мог поменять кто-то ещё (параметры KDE).
    const KConfig config(QStringLiteral("powerdevilrc"));
    QVariantList profiles;
    const QStringList shown = m_hasBattery ? QStringList{QStringLiteral("AC"), QStringLiteral("Battery")} : QStringList{QStringLiteral("AC")};
    for (const QString &profile : shown) {
        const KConfigGroup display = config.group(profile).group(QStringLiteral("Display"));
        const KConfigGroup suspend = config.group(profile).group(QStringLiteral("SuspendAndShutdown"));

        const int dim = display.readEntry("DimDisplayWhenIdle", true)
            ? display.readEntry("DimDisplayIdleTimeoutSec", pick(profile, 300, 120, 60))
            : 0;
        const int off = display.readEntry("TurnOffDisplayWhenIdle", true)
            ? display.readEntry("TurnOffDisplayIdleTimeoutSec", pick(profile, 600, 300, 120))
            : 0;
        const uint suspendDefault = (!m_isVM && m_canSuspend) ? Sleep : NoAction;
        const int sleep = suspend.readEntry("AutoSuspendAction", suspendDefault) != NoAction
            ? suspend.readEntry("AutoSuspendIdleTimeoutSec", pick(profile, 900, 600, 300))
            : 0;

        profiles.append(QVariantMap{{QStringLiteral("id"), profile},
                                    {QStringLiteral("title"), profile == QLatin1String("AC") ? QStringLiteral("От сети") : QStringLiteral("От батареи")},
                                    {QStringLiteral("dim"), dim},
                                    {QStringLiteral("off"), off},
                                    {QStringLiteral("sleep"), sleep}});
    }
    m_profiles = profiles;

    const KConfigGroup acSuspend = config.group(QStringLiteral("AC")).group(QStringLiteral("SuspendAndShutdown"));
    m_powerButton = int(acSuspend.readEntry("PowerButtonAction", PromptLogoutDialog));
    m_lidAction = int(acSuspend.readEntry("LidAction", m_isVM ? NoAction : m_canSuspend ? Sleep : TurnOffScreen));
    Q_EMIT changed();
}

void Power::setTimeout(const QString &profile, const QString &kind, int seconds)
{
    if (!allProfiles.contains(profile) || seconds < 0)
        return;
    KConfig config(QStringLiteral("powerdevilrc"));
    if (kind == QLatin1String("dim") || kind == QLatin1String("off")) {
        KConfigGroup display = config.group(profile).group(QStringLiteral("Display"));
        const bool dim = kind == QLatin1String("dim");
        display.writeEntry(dim ? "DimDisplayWhenIdle" : "TurnOffDisplayWhenIdle", seconds > 0);
        if (seconds > 0)
            display.writeEntry(dim ? "DimDisplayIdleTimeoutSec" : "TurnOffDisplayIdleTimeoutSec", seconds);
    } else if (kind == QLatin1String("sleep")) {
        KConfigGroup suspend = config.group(profile).group(QStringLiteral("SuspendAndShutdown"));
        if (seconds == 0) {
            suspend.writeEntry("AutoSuspendAction", NoAction);
        } else {
            // Был выбран не сон, а, скажем, гибернация в параметрах KDE — оставляем.
            if (suspend.readEntry("AutoSuspendAction", NoAction) == NoAction)
                suspend.writeEntry("AutoSuspendAction", Sleep);
            suspend.writeEntry("AutoSuspendIdleTimeoutSec", seconds);
        }
    } else {
        return;
    }
    if (!config.sync()) {
        m_error = QStringLiteral("Не удалось сохранить настройки питания.");
        Q_EMIT changed();
        return;
    }
    notifyDaemon();
    load();
}

void Power::setPowerButton(int action)
{
    KConfig config(QStringLiteral("powerdevilrc"));
    for (const QString &profile : allProfiles)
        config.group(profile).group(QStringLiteral("SuspendAndShutdown")).writeEntry("PowerButtonAction", uint(action));
    if (!config.sync()) {
        m_error = QStringLiteral("Не удалось сохранить настройки питания.");
        Q_EMIT changed();
        return;
    }
    notifyDaemon();
    load();
}

void Power::setLidAction(int action)
{
    KConfig config(QStringLiteral("powerdevilrc"));
    for (const QString &profile : allProfiles)
        config.group(profile).group(QStringLiteral("SuspendAndShutdown")).writeEntry("LidAction", uint(action));
    if (!config.sync()) {
        m_error = QStringLiteral("Не удалось сохранить настройки питания.");
        Q_EMIT changed();
        return;
    }
    notifyDaemon();
    load();
}

void Power::notifyDaemon()
{
    // Как модуль параметров KDE: перечитать файл и заново применить профиль.
    auto reparse = QDBusMessage::createMethodCall(pmService, pmPath, pmService, QStringLiteral("reparseConfiguration"));
    QDBusConnection::sessionBus().asyncCall(reparse);
    auto refresh = QDBusMessage::createMethodCall(pmService, pmPath, pmService, QStringLiteral("refreshStatus"));
    auto *watcher = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(refresh, 5000), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *call) {
        call->deleteLater();
        const QString error = call->isError()
            ? QStringLiteral("Служба питания не ответила: настройки сохранены и заработают после нового входа.")
            : QString();
        if (error != m_error) {
            m_error = error;
            Q_EMIT changed();
        }
    });
}
