#include "network.h"

#include <NetworkManagerQt/AccessPoint>
#include <NetworkManagerQt/ActiveConnection>
#include <NetworkManagerQt/Connection>
#include <NetworkManagerQt/ConnectionSettings>
#include <NetworkManagerQt/Ipv4Setting>
#include <NetworkManagerQt/Manager>
#include <NetworkManagerQt/Settings>
#include <NetworkManagerQt/WiredDevice>
#include <NetworkManagerQt/WirelessDevice>
#include <NetworkManagerQt/WirelessSecuritySetting>
#include <NetworkManagerQt/WirelessSetting>

#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDBusMetaType>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QFileInfo>
#include <QHostAddress>
#include <QProcess>
#include <QRegularExpression>
#include <QUrl>
#include <QUuid>

using namespace NetworkManager;

namespace
{
const QString nmService = QStringLiteral("org.freedesktop.NetworkManager");
const QString connectionInterface = QStringLiteral("org.freedesktop.NetworkManager.Settings.Connection");

QString kindOf(ConnectionSettings::ConnectionType type)
{
    switch (type) {
    case ConnectionSettings::Wireless:
        return QStringLiteral("wifi");
    case ConnectionSettings::Wired:
        return QStringLiteral("wired");
    case ConnectionSettings::Vpn:
    case ConnectionSettings::WireGuard:
        return QStringLiteral("vpn");
    default:
        return QStringLiteral("other");
    }
}

QString kindText(ConnectionSettings::ConnectionType type, const ConnectionSettings::Ptr &settings)
{
    switch (type) {
    case ConnectionSettings::Wireless: {
        const auto wireless = settings->setting(Setting::Wireless).staticCast<WirelessSetting>();
        if (wireless && wireless->mode() == WirelessSetting::Ap)
            return QStringLiteral("Точка доступа Wi‑Fi");
        return wireless && wireless->hidden() ? QStringLiteral("Wi‑Fi, скрытая") : QStringLiteral("Wi‑Fi");
    }
    case ConnectionSettings::Wired:
        return QStringLiteral("Кабель");
    case ConnectionSettings::Vpn:
        return QStringLiteral("VPN");
    case ConnectionSettings::WireGuard:
        return QStringLiteral("VPN (WireGuard)");
    case ConnectionSettings::Gsm:
    case ConnectionSettings::Cdma:
        return QStringLiteral("Мобильная сеть");
    case ConnectionSettings::Bluetooth:
        return QStringLiteral("Через Bluetooth");
    default:
        return QStringLiteral("Другое");
    }
}

// Показываем только то, что человек сам заводил; служебное (lo, мосты
// контейнеров, tun) — нет.
bool shown(ConnectionSettings::ConnectionType type)
{
    switch (type) {
    case ConnectionSettings::Wireless:
    case ConnectionSettings::Wired:
    case ConnectionSettings::Vpn:
    case ConnectionSettings::WireGuard:
    case ConnectionSettings::Gsm:
    case ConnectionSettings::Cdma:
    case ConnectionSettings::Bluetooth:
    case ConnectionSettings::Pppoe:
        return true;
    default:
        return false;
    }
}

// "255.255.255.0" или "24" → 24; -1 — не разобрали.
int prefixOf(const QString &mask)
{
    const QString text = mask.trimmed().remove(QLatin1Char('/'));
    bool number = false;
    const int value = text.toInt(&number);
    if (number)
        return value >= 1 && value <= 32 ? value : -1;
    QHostAddress address;
    if (!address.setAddress(text) || address.protocol() != QAbstractSocket::IPv4Protocol)
        return -1;
    const quint32 bits = address.toIPv4Address();
    int prefix = 0;
    while (prefix < 32 && (bits & (0x80000000u >> prefix)))
        ++prefix;
    // Маска — единицы, потом нули, без дыр.
    if (prefix < 32 && (bits << prefix) != 0)
        return -1;
    return prefix >= 1 ? prefix : -1;
}

QString maskOf(int prefix)
{
    if (prefix <= 0 || prefix > 32)
        return {};
    return QHostAddress(prefix == 32 ? 0xffffffffu : ~(0xffffffffu >> prefix)).toString();
}

bool isIpv4(const QString &text)
{
    QHostAddress address;
    return address.setAddress(text.trimmed()) && address.protocol() == QAbstractSocket::IPv4Protocol;
}

QString speedText(int mbits)
{
    if (mbits <= 0)
        return {};
    if (mbits >= 1000 && mbits % 1000 == 0)
        return QStringLiteral("%1 Гбит/с").arg(mbits / 1000);
    return QStringLiteral("%1 Мбит/с").arg(mbits);
}
} // namespace

Network::Network(QObject *parent)
    : QObject(parent)
    , m_deviceModel(new KeyedModel(QStringLiteral("uni"), this))
    , m_connectionModel(new KeyedModel(QStringLiteral("uuid"), this))
{
    qDBusRegisterMetaType<NMVariantMapMap>();
    qDBusRegisterMetaType<NMVariantMapList>();

    // Много сигналов подряд (подключение — десяток смен состояния) —
    // один пересчёт.
    m_rebuild.setSingleShot(true);
    m_rebuild.setInterval(80);
    connect(&m_rebuild, &QTimer::timeout, this, &Network::rebuild);

    auto *manager = notifier();
    connect(manager, &Notifier::deviceAdded, this, &Network::scheduleRebuild);
    connect(manager, &Notifier::deviceRemoved, this, &Network::scheduleRebuild);
    connect(manager, &Notifier::activeConnectionsChanged, this, &Network::scheduleRebuild);
    connect(manager, &Notifier::wirelessEnabledChanged, this, &Network::scheduleRebuild);
    connect(manager, &Notifier::wirelessHardwareEnabledChanged, this, &Network::scheduleRebuild);
    connect(manager, &Notifier::serviceAppeared, this, &Network::scheduleRebuild);
    connect(manager, &Notifier::serviceDisappeared, this, &Network::scheduleRebuild);
    connect(settingsNotifier(), &SettingsNotifier::connectionAdded, this, &Network::scheduleRebuild);
    connect(settingsNotifier(), &SettingsNotifier::connectionRemoved, this, &Network::scheduleRebuild);
    rebuild();
}

bool Network::wifiEnabled() const
{
    return isWirelessEnabled();
}

bool Network::wifiHardwareBlocked() const
{
    return !isWirelessHardwareEnabled();
}

bool Network::openVpnSupported() const
{
    return QFileInfo::exists(QStringLiteral("/usr/lib/NetworkManager/VPN/nm-openvpn-service.name"));
}

void Network::scheduleRebuild()
{
    m_rebuild.start();
}

void Network::rebuild()
{
    m_available = QDBusConnection::systemBus().interface()
        && QDBusConnection::systemBus().interface()->isServiceRegistered(nmService);

    // Подключённое сейчас: uuid → состояние.
    QHash<QString, ActiveConnection::State> activeStates;
    for (const ActiveConnection::Ptr &active : activeConnections())
        activeStates.insert(active->uuid(), active->state());

    m_devices.clear();
    m_wifiPresent = false;
    // Адреса подключённых сетей сейчас (uuid → …) — подставить в «Вручную».
    QHash<QString, QVariantMap> current;
    for (const Device::Ptr &device : networkInterfaces()) {
        // Каждый сигнал — по разу (UniqueConnection не даёт копить их).
        connect(device.data(), &Device::stateChanged, this, &Network::scheduleRebuild, Qt::UniqueConnection);
        connect(device.data(), &Device::activeConnectionChanged, this, &Network::scheduleRebuild, Qt::UniqueConnection);
        connect(device.data(), &Device::ipV4ConfigChanged, this, &Network::scheduleRebuild, Qt::UniqueConnection);

        const bool wifi = device->type() == Device::Wifi;
        const bool wired = device->type() == Device::Ethernet;
        if ((!wifi && !wired) || device->state() == Device::Unmanaged)
            continue;
        if (wifi)
            m_wifiPresent = true;

        const ActiveConnection::Ptr active = device->activeConnection();
        const QString name = active ? active->id() : QString();
        QString state;
        QString status;
        switch (device->state()) {
        case Device::Activated:
            state = QStringLiteral("connected");
            status = wifi ? QStringLiteral("Подключено к «%1»").arg(name) : QStringLiteral("Подключено");
            break;
        case Device::Preparing:
        case Device::ConfiguringHardware:
        case Device::NeedAuth:
        case Device::ConfiguringIp:
        case Device::CheckingIp:
        case Device::WaitingForSecondaries:
            state = QStringLiteral("connecting");
            status = name.isEmpty() ? QStringLiteral("Подключение…") : QStringLiteral("Подключение к «%1»…").arg(name);
            break;
        case Device::Deactivating:
            state = QStringLiteral("connecting");
            status = QStringLiteral("Отключение…");
            break;
        case Device::Unavailable:
            state = QStringLiteral("unavailable");
            status = wired ? QStringLiteral("Кабель не вставлен")
                   : !isWirelessEnabled() || !isWirelessHardwareEnabled() ? QStringLiteral("Выключен")
                   : QStringLiteral("Недоступен");
            break;
        default:
            state = QStringLiteral("disconnected");
            status = QStringLiteral("Не подключено");
            break;
        }

        QVariantList details;
        auto add = [&details](const QString &label, const QString &value) {
            if (!value.isEmpty())
                details << QVariant(QStringList{label, value});
        };
        if (device->state() == Device::Activated) {
            const IpConfig ip = device->ipV4Config();
            QVariantMap now;
            if (!ip.addresses().isEmpty()) {
                const IpAddress first = ip.addresses().constFirst();
                add(QStringLiteral("IP-адрес"), first.ip().toString());
                add(QStringLiteral("Маска"), maskOf(first.prefixLength()));
                now.insert(QStringLiteral("address"), first.ip().toString());
                now.insert(QStringLiteral("prefix"), maskOf(first.prefixLength()));
            }
            add(QStringLiteral("Шлюз"), ip.gateway());
            now.insert(QStringLiteral("gateway"), ip.gateway());
            QStringList dns;
            for (const QHostAddress &server : ip.nameservers())
                dns << server.toString();
            add(QStringLiteral("DNS"), dns.join(QStringLiteral(", ")));
            now.insert(QStringLiteral("dns"), dns.join(QStringLiteral(", ")));
            if (active)
                current.insert(active->uuid(), now);
        }
        if (wifi) {
            const auto wireless = device.objectCast<WirelessDevice>();
            if (device->state() == Device::Activated && wireless->activeAccessPoint()) {
                add(QStringLiteral("Сигнал"), QStringLiteral("%1 %").arg(wireless->activeAccessPoint()->signalStrength()));
                add(QStringLiteral("Скорость"), speedText(wireless->bitRate() / 1000));
            }
            add(QStringLiteral("MAC-адрес"), wireless->hardwareAddress());
        } else {
            const auto ethernet = device.objectCast<WiredDevice>();
            if (device->state() == Device::Activated)
                add(QStringLiteral("Скорость"), speedText(ethernet->bitRate()));
            add(QStringLiteral("MAC-адрес"), ethernet->hardwareAddress());
        }
        add(QStringLiteral("Устройство"), device->interfaceName());

        m_devices << QVariantMap{
            {QStringLiteral("uni"), device->uni()},
            {QStringLiteral("kind"), wifi ? QStringLiteral("wifi") : QStringLiteral("wired")},
            {QStringLiteral("title"), wifi ? QStringLiteral("Wi‑Fi") : QStringLiteral("Кабель")},
            {QStringLiteral("state"), state},
            {QStringLiteral("status"), status},
            {QStringLiteral("details"), details},
        };
    }
    // Кабель первым, потом Wi‑Fi; два одинаковых — по имени устройства.
    std::stable_sort(m_devices.begin(), m_devices.end(), [](const QVariant &a, const QVariant &b) {
        return a.toMap().value(QStringLiteral("kind")).toString() == QLatin1String("wired")
            && b.toMap().value(QStringLiteral("kind")).toString() != QLatin1String("wired");
    });

    struct Entry {
        QVariantMap map;
        int rank;
        qint64 used;
        QString name;
        int kind;
    };
    QList<Entry> entries;
    for (const Connection::Ptr &connection : listConnections()) {
        connect(connection.data(), &Connection::updated, this, &Network::scheduleRebuild, Qt::UniqueConnection);
        const ConnectionSettings::Ptr settings = connection->settings();
        if (!settings || !shown(settings->connectionType()))
            continue;
        const auto type = settings->connectionType();
        const QString uuid = connection->uuid();
        const auto state = activeStates.value(uuid, ActiveConnection::Unknown);
        const bool active = state == ActiveConnection::Activated;
        const bool activating = state == ActiveConnection::Activating;

        const auto ipv4 = settings->setting(Setting::Ipv4).staticCast<Ipv4Setting>();
        const bool manual = ipv4 && ipv4->method() == Ipv4Setting::Manual && !ipv4->addresses().isEmpty();
        QString address, prefix, gateway;
        if (manual) {
            const IpAddress first = ipv4->addresses().constFirst();
            address = first.ip().toString();
            prefix = maskOf(first.prefixLength());
            gateway = ipv4->gateway();
        }
        QStringList dns;
        if (ipv4)
            for (const QHostAddress &server : ipv4->dns())
                dns << server.toString();

        bool secured = false;
        if (type == ConnectionSettings::Wireless) {
            const auto security = settings->setting(Setting::WirelessSecurity).staticCast<WirelessSecuritySetting>();
            secured = security && (security->keyMgmt() == WirelessSecuritySetting::WpaPsk || security->keyMgmt() == WirelessSecuritySetting::SAE);
        }
        const auto metered = settings->metered();

        entries << Entry{
            QVariantMap{
                {QStringLiteral("uuid"), uuid},
                {QStringLiteral("name"), connection->name()},
                {QStringLiteral("kind"), kindOf(type)},
                {QStringLiteral("kindText"), kindText(type, settings)},
                {QStringLiteral("active"), active},
                {QStringLiteral("activating"), activating},
                {QStringLiteral("autoconnect"), settings->autoconnect()},
                {QStringLiteral("metered"), metered == ConnectionSettings::MeteredYes || metered == ConnectionSettings::MeteredGuessYes},
                {QStringLiteral("secured"), secured},
                {QStringLiteral("hasIpv4"), bool(ipv4)},
                {QStringLiteral("ipManual"), manual},
                {QStringLiteral("address"), address},
                {QStringLiteral("prefix"), prefix},
                {QStringLiteral("gateway"), gateway},
                {QStringLiteral("dnsManual"), ipv4 && ipv4->ignoreAutoDns() && !dns.isEmpty()},
                {QStringLiteral("dns"), dns.join(QStringLiteral(", "))},
                {QStringLiteral("current"), current.value(uuid)},
            },
            active ? 0 : activating ? 1 : 2,
            settings->timestamp().isValid() ? settings->timestamp().toSecsSinceEpoch() : 0,
            connection->name(),
            type == ConnectionSettings::Wired ? 0 : type == ConnectionSettings::Wireless ? 1 : 2,
        };
    }
    // Подключённые (кабель, Wi‑Fi, VPN — не прыгают местами, пока
    // NetworkManager обновляет им время), потом по последнему подключению.
    std::sort(entries.begin(), entries.end(), [](const Entry &a, const Entry &b) {
        if (a.rank != b.rank)
            return a.rank < b.rank;
        if (a.rank < 2 && a.kind != b.kind)
            return a.kind < b.kind;
        if (a.rank < 2)
            return a.name.localeAwareCompare(b.name) < 0;
        if (a.used != b.used)
            return a.used > b.used;
        return a.name.localeAwareCompare(b.name) < 0;
    });
    m_connections.clear();
    for (const Entry &entry : std::as_const(entries))
        m_connections << entry.map;

    m_deviceModel->setItems(m_devices);
    m_connectionModel->setItems(m_connections);
    Q_EMIT changed();
}

void Network::setMessage(const QString &text, bool error)
{
    m_message = text;
    m_messageIsError = error;
    Q_EMIT messageChanged();
}

void Network::clearMessage()
{
    setMessage({}, false);
}

QString Network::explain(const QString &error)
{
    if (error.contains(QLatin1String("Insufficient privileges"), Qt::CaseInsensitive)
        || error.contains(QLatin1String("not authorized"), Qt::CaseInsensitive)
        || error.contains(QLatin1String("PermissionDenied"), Qt::CaseInsensitive))
        return QStringLiteral("нет прав (пароль не введён?)");
    if (error.contains(QLatin1String("psk"), Qt::CaseInsensitive))
        return QStringLiteral("пароль Wi‑Fi — от 8 до 63 символов");
    if (error.contains(QLatin1String("No suitable device"), Qt::CaseInsensitive)
        || error.contains(QLatin1String("not available"), Qt::CaseInsensitive))
        return QStringLiteral("сеть сейчас недоступна");
    return error;
}

void Network::watch(const QDBusPendingCall &call, const QString &uuid, const QString &failure, const QString &success, bool inPlace)
{
    auto *watcher = new QDBusPendingCallWatcher(call, this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, watcher, uuid, failure, success, inPlace] {
        watcher->deleteLater();
        if (watcher->isError()) {
            const QString reason = explain(watcher->error().message());
            if (inPlace)
                Q_EMIT saved(uuid, reason);
            else
                setMessage(failure + QStringLiteral(": ") + reason, true);
        } else {
            if (inPlace)
                Q_EMIT saved(uuid, {});
            else if (!success.isEmpty())
                setMessage(success, false);
        }
        scheduleRebuild();
    });
}

void Network::setWifiEnabled(bool enabled)
{
    setWirelessEnabled(enabled);
}

void Network::activate(const QString &uuid)
{
    const Connection::Ptr connection = findConnectionByUuid(uuid);
    if (!connection)
        return;
    clearMessage();
    // Устройство подходящего типа: Wi‑Fi — для Wi‑Fi, кабель — для кабеля;
    // VPN — без устройства (NetworkManager выберет сам).
    // Сначала то, на котором сеть доступна (NetworkManager сам знает),
    // потом любое включённое того же типа; неуправляемые — мимо.
    QString deviceUni;
    QString fallback;
    const auto type = connection->settings()->connectionType();
    for (const Device::Ptr &device : networkInterfaces()) {
        const bool fits = (type == ConnectionSettings::Wireless && device->type() == Device::Wifi)
            || (type == ConnectionSettings::Wired && device->type() == Device::Ethernet);
        if (!fits || device->state() == Device::Unmanaged)
            continue;
        bool available = false;
        for (const Connection::Ptr &candidate : device->availableConnections())
            available = available || candidate->uuid() == uuid;
        if (available) {
            deviceUni = device->uni();
            break;
        }
        if (fallback.isEmpty() && device->state() != Device::Unavailable)
            fallback = device->uni();
    }
    if (deviceUni.isEmpty())
        deviceUni = fallback;
    watch(activateConnection(connection->path(), deviceUni, QString()), uuid,
          QStringLiteral("Не удалось подключить «%1»").arg(connection->name()));
}

void Network::reapply(const QString &uuid)
{
    // Подключённая сеть: новые адреса — сразу, без разрыва (Reapply);
    // не вышло (такое не применяется на ходу) — переподключить.
    for (const Device::Ptr &device : networkInterfaces()) {
        const ActiveConnection::Ptr active = device->activeConnection();
        if (!active || active->uuid() != uuid)
            continue;
        auto *watcher = new QDBusPendingCallWatcher(device->reapplyConnection({}, 0, 0), this);
        connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, watcher, uuid] {
            watcher->deleteLater();
            if (watcher->isError())
                activate(uuid);
            else
                scheduleRebuild();
        });
        return;
    }
    activate(uuid);
}

void Network::deactivate(const QString &uuid)
{
    for (const ActiveConnection::Ptr &active : activeConnections()) {
        if (active->uuid() == uuid) {
            clearMessage();
            watch(deactivateConnection(active->path()), uuid, QStringLiteral("Не удалось отключить «%1»").arg(active->id()));
            return;
        }
    }
}

// Правка «как есть»: берём настройки из NetworkManager целиком (GetSettings),
// меняем только своё и отдаём обратно (Update). Через объекты
// NetworkManagerQt нельзя — они теряют свойства, которых не знают.
static void updateRaw(Network *self, const QString &uuid, std::function<void(NMVariantMapMap &)> change,
                      std::function<void(const QDBusPendingCall &)> done)
{
    const Connection::Ptr connection = findConnectionByUuid(uuid);
    if (!connection)
        return;
    const QString path = connection->path();
    QDBusMessage get = QDBusMessage::createMethodCall(nmService, path, connectionInterface, QStringLiteral("GetSettings"));
    auto *watcher = new QDBusPendingCallWatcher(QDBusConnection::systemBus().asyncCall(get), self);
    QObject::connect(watcher, &QDBusPendingCallWatcher::finished, self, [watcher, path, change, done] {
        watcher->deleteLater();
        QDBusPendingReply<NMVariantMapMap> reply = *watcher;
        if (reply.isError()) {
            done(reply);
            return;
        }
        NMVariantMapMap settings = reply.value();
        change(settings);
        QDBusMessage update = QDBusMessage::createMethodCall(nmService, path, connectionInterface, QStringLiteral("Update"));
        update << QVariant::fromValue(settings);
        done(QDBusConnection::systemBus().asyncCall(update));
    });
}

void Network::setAutoconnect(const QString &uuid, bool value)
{
    clearMessage();
    updateRaw(this, uuid, [value](NMVariantMapMap &s) {
        s[QStringLiteral("connection")][QStringLiteral("autoconnect")] = value;
    }, [this, uuid](const QDBusPendingCall &call) {
        watch(call, uuid, QStringLiteral("Не удалось изменить"), {}, true);
    });
}

void Network::setMetered(const QString &uuid, bool value)
{
    clearMessage();
    // 1 — лимитное, 2 — нет (NM_METERED_YES/NO).
    updateRaw(this, uuid, [value](NMVariantMapMap &s) {
        s[QStringLiteral("connection")][QStringLiteral("metered")] = value ? 1 : 2;
    }, [this, uuid](const QDBusPendingCall &call) {
        watch(call, uuid, QStringLiteral("Не удалось изменить"), {}, true);
    });
}

QString Network::saveAddressing(const QString &uuid, bool manual, const QString &address, const QString &mask,
                                const QString &gateway, bool dnsManual, const QString &dns)
{
    // Проверяем здесь — чтобы сказать по-человечески, что не так.
    int prefix = 0;
    if (manual) {
        if (!isIpv4(address))
            return QStringLiteral("IP-адрес — четыре числа через точку, например 192.168.1.20");
        prefix = prefixOf(mask);
        if (prefix < 0)
            return QStringLiteral("Маска — например 255.255.255.0 или 24");
        if (!gateway.trimmed().isEmpty() && !isIpv4(gateway))
            return QStringLiteral("Шлюз — адрес вида 192.168.1.1 (или пусто)");
    }
    QStringList servers;
    if (dnsManual) {
        servers = dns.split(QRegularExpression(QStringLiteral("[,;\\s]+")), Qt::SkipEmptyParts);
        if (servers.isEmpty())
            return QStringLiteral("Укажите хотя бы один DNS-сервер, например 1.1.1.1");
        for (const QString &server : std::as_const(servers))
            if (!isIpv4(server))
                return QStringLiteral("«%1» — не адрес DNS-сервера").arg(server);
    }
    clearMessage();
    const QString addr = address.trimmed();
    const QString gw = gateway.trimmed();
    updateRaw(this, uuid, [=](NMVariantMapMap &s) {
        QVariantMap &ipv4 = s[QStringLiteral("ipv4")];
        // Устаревшие ключи (addresses, dns) — убрать: иначе NM возьмёт их.
        ipv4.remove(QStringLiteral("addresses"));
        ipv4.remove(QStringLiteral("dns"));
        if (manual) {
            ipv4[QStringLiteral("method")] = QStringLiteral("manual");
            ipv4[QStringLiteral("address-data")] = QVariant::fromValue(NMVariantMapList{QVariantMap{
                {QStringLiteral("address"), addr},
                {QStringLiteral("prefix"), uint(prefix)},
            }});
            if (gw.isEmpty())
                ipv4.remove(QStringLiteral("gateway"));
            else
                ipv4[QStringLiteral("gateway")] = gw;
        } else {
            ipv4[QStringLiteral("method")] = QStringLiteral("auto");
            ipv4[QStringLiteral("address-data")] = QVariant::fromValue(NMVariantMapList{});
            ipv4.remove(QStringLiteral("gateway"));
        }
        ipv4[QStringLiteral("dns-data")] = dnsManual ? servers : QStringList{};
        ipv4[QStringLiteral("ignore-auto-dns")] = dnsManual;
    }, [this, uuid](const QDBusPendingCall &call) {
        // Новые адреса действуют после переподключения — его сделает QML,
        // если сеть подключена.
        watch(call, uuid, QStringLiteral("Не удалось сохранить"), QStringLiteral("Сохранено"), true);
    });
    return {};
}

void Network::requestPassword(const QString &uuid)
{
    const Connection::Ptr connection = findConnectionByUuid(uuid);
    if (!connection)
        return;
    auto *watcher = new QDBusPendingCallWatcher(connection->secrets(QStringLiteral("802-11-wireless-security")), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, watcher, uuid] {
        watcher->deleteLater();
        QDBusPendingReply<NMVariantMapMap> reply = *watcher;
        if (reply.isError()) {
            Q_EMIT passwordReady(uuid, {}, explain(reply.error().message()));
            return;
        }
        const QString psk = reply.value().value(QStringLiteral("802-11-wireless-security")).value(QStringLiteral("psk")).toString();
        Q_EMIT passwordReady(uuid, psk, psk.isEmpty() ? QStringLiteral("пароль не сохранён") : QString());
    });
}

void Network::setPassword(const QString &uuid, const QString &password)
{
    if (password.size() < 8 || password.size() > 63) {
        Q_EMIT saved(uuid, QStringLiteral("пароль Wi‑Fi — от 8 до 63 символов"));
        return;
    }
    clearMessage();
    updateRaw(this, uuid, [password](NMVariantMapMap &s) {
        QVariantMap &security = s[QStringLiteral("802-11-wireless-security")];
        security[QStringLiteral("psk")] = password;
        // Хранить в системе, а не спрашивать у агента каждый раз.
        security[QStringLiteral("psk-flags")] = 0u;
    }, [this, uuid](const QDBusPendingCall &call) {
        watch(call, uuid, QStringLiteral("Не удалось сменить пароль"), QStringLiteral("Пароль сохранён"), true);
    });
}

void Network::forget(const QString &uuid)
{
    const Connection::Ptr connection = findConnectionByUuid(uuid);
    if (!connection)
        return;
    clearMessage();
    watch(connection->remove(), uuid, QStringLiteral("Не удалось забыть «%1»").arg(connection->name()),
          QStringLiteral("«%1» забыта").arg(connection->name()));
}

void Network::connectHidden(const QString &ssid, const QString &password)
{
    const QString name = ssid.trimmed();
    if (name.isEmpty())
        return;
    if (!password.isEmpty() && (password.size() < 8 || password.size() > 63)) {
        setMessage(QStringLiteral("Пароль Wi‑Fi — от 8 до 63 символов"), true);
        return;
    }
    QString deviceUni;
    for (const Device::Ptr &device : networkInterfaces())
        if (device->type() == Device::Wifi && device->state() != Device::Unmanaged)
            deviceUni = device->uni();
    if (deviceUni.isEmpty()) {
        setMessage(QStringLiteral("Нет Wi‑Fi"), true);
        return;
    }
    NMVariantMapMap settings;
    settings[QStringLiteral("connection")] = QVariantMap{
        {QStringLiteral("id"), name},
        {QStringLiteral("uuid"), QUuid::createUuid().toString(QUuid::WithoutBraces)},
        {QStringLiteral("type"), QStringLiteral("802-11-wireless")},
    };
    settings[QStringLiteral("802-11-wireless")] = QVariantMap{
        {QStringLiteral("ssid"), name.toUtf8()},
        {QStringLiteral("hidden"), true},
        {QStringLiteral("mode"), QStringLiteral("infrastructure")},
    };
    if (!password.isEmpty()) {
        settings[QStringLiteral("802-11-wireless-security")] = QVariantMap{
            {QStringLiteral("key-mgmt"), QStringLiteral("wpa-psk")},
            {QStringLiteral("psk"), password},
        };
    }
    clearMessage();
    watch(addAndActivateConnection(settings, deviceUni, QString()), QString(),
          QStringLiteral("Не удалось подключиться к «%1»").arg(name));
}

void Network::importVpn(const QString &file)
{
    const QString path = file.startsWith(QLatin1String("file:")) ? QUrl(file).toLocalFile() : file;
    const QString suffix = QFileInfo(path).suffix().toLower();
    QString type;
    if (suffix == QLatin1String("conf"))
        type = QStringLiteral("wireguard");
    else if (suffix == QLatin1String("ovpn") && openVpnSupported())
        type = QStringLiteral("openvpn");
    if (type.isEmpty()) {
        setMessage(suffix == QLatin1String("ovpn") ? QStringLiteral("Для OpenVPN нужен пакет networkmanager-openvpn")
                                                   : QStringLiteral("Подходят файлы WireGuard (.conf) и OpenVPN (.ovpn)"),
                   true);
        return;
    }
    clearMessage();
    // Разбор файлов VPN есть только в libnm (nmcli), не в D-Bus.
    auto *process = new QProcess(this);
    process->setProcessChannelMode(QProcess::MergedChannels);
    connect(process, &QProcess::finished, this, [this, process, path](int code, QProcess::ExitStatus status) {
        process->deleteLater();
        const QString output = QString::fromUtf8(process->readAll()).trimmed();
        const QString name = QFileInfo(path).fileName();
        if (status == QProcess::NormalExit && code == 0) {
            // NetworkManager включает новое сразу и потом сам при каждом
            // входе. VPN с «весь трафик через сервер» и недоступным сервером
            // оставил бы без интернета — пусть включают сами, когда нужно.
            static const QRegularExpression uuidPattern(QStringLiteral("[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"));
            const QString uuid = uuidPattern.match(output).captured(0);
            if (!uuid.isEmpty()) {
                setAutoconnect(uuid, false);
                // Подключение начинается чуть позже добавления — отключить, когда начнётся.
                deactivate(uuid);
                QTimer::singleShot(1500, this, [this, uuid] { deactivate(uuid); });
            }
            setMessage(QStringLiteral("VPN «%1» добавлен — «Подключить» в списке ниже").arg(QFileInfo(path).completeBaseName()), false);
            return;
        }
        // nmcli пишет «Ошибка: сбой импорта «путь»: причина» — оставить причину.
        QString reason = output.section(QStringLiteral("»: "), 1).trimmed();
        if (reason.isEmpty() || reason.contains(QLatin1String("строка")) || reason.contains(QLatin1String("line")))
            reason = QStringLiteral("это не файл настроек VPN или он повреждён");
        setMessage(QStringLiteral("«%1» не подошёл: %2").arg(name, reason), true);
    });
    connect(process, &QProcess::errorOccurred, this, [this, process](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart) {
            setMessage(QStringLiteral("Не удалось добавить VPN: нет nmcli"), true);
            process->deleteLater();
        }
    });
    process->start(QStringLiteral("nmcli"), {QStringLiteral("connection"), QStringLiteral("import"), QStringLiteral("type"), type,
                                             QStringLiteral("file"), path});
}
