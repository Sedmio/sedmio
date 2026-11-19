#pragma once

#include <QDBusPendingCall>
#include <QObject>
#include <QQmlEngine>
#include <QTimer>
#include <QVariantList>

#include "keyedmodel.h"

// «Сеть»: что подключено сейчас (кабель, Wi‑Fi — адрес, шлюз, DNS) и
// сохранённые сети — подключаться ли самой, лимитная ли, пароль, свой
// IP-адрес и DNS, забыть. Плюс скрытая сеть Wi‑Fi и VPN из файла.
// Всё через NetworkManager (NetworkManagerQt); список сетей рядом и
// подключение к новой — в панели оболочки.
class Network : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(bool available READ available NOTIFY changed)
    Q_PROPERTY(bool wifiPresent READ wifiPresent NOTIFY changed)
    Q_PROPERTY(bool wifiEnabled READ wifiEnabled NOTIFY changed)
    // Выключен кнопкой или переключателем на корпусе (rfkill).
    Q_PROPERTY(bool wifiHardwareBlocked READ wifiHardwareBlocked NOTIFY changed)
    // [{uni, kind: "wifi"|"wired", title, state, status, details: [[подпись, значение]]}]
    Q_PROPERTY(QVariantList devices READ devices NOTIFY changed)
    // [{uuid, name, kind: "wifi"|"wired"|"vpn"|"other", kindText, active, activating,
    //   autoconnect, metered, secured, ipManual, address, prefix, gateway, dnsManual, dns}]
    Q_PROPERTY(QVariantList connections READ connections NOTIFY changed)
    // Те же списки моделью — для Repeater (строки не пересоздаются).
    Q_PROPERTY(KeyedModel *deviceModel READ deviceModel CONSTANT)
    Q_PROPERTY(KeyedModel *connectionModel READ connectionModel CONSTANT)
    // Можно ли импортировать OpenVPN (.ovpn): стоит ли модуль NetworkManager.
    Q_PROPERTY(bool openVpnSupported READ openVpnSupported CONSTANT)
    Q_PROPERTY(QString message READ message NOTIFY messageChanged)
    Q_PROPERTY(bool messageIsError READ messageIsError NOTIFY messageChanged)

public:
    explicit Network(QObject *parent = nullptr);

    bool available() const { return m_available; }
    bool wifiPresent() const { return m_wifiPresent; }
    bool wifiEnabled() const;
    bool wifiHardwareBlocked() const;
    QVariantList devices() const { return m_devices; }
    QVariantList connections() const { return m_connections; }
    KeyedModel *deviceModel() const { return m_deviceModel; }
    KeyedModel *connectionModel() const { return m_connectionModel; }
    bool openVpnSupported() const;
    QString message() const { return m_message; }
    bool messageIsError() const { return m_messageIsError; }

    Q_INVOKABLE void setWifiEnabled(bool enabled);
    Q_INVOKABLE void activate(const QString &uuid);
    Q_INVOKABLE void deactivate(const QString &uuid);
    // Применить сохранённое к подключённой сети.
    Q_INVOKABLE void reapply(const QString &uuid);
    Q_INVOKABLE void setAutoconnect(const QString &uuid, bool value);
    Q_INVOKABLE void setMetered(const QString &uuid, bool value);
    // Пусто в address — автоматически (DHCP); dns пусто — DNS сети.
    Q_INVOKABLE QString saveAddressing(const QString &uuid, bool manual, const QString &address, const QString &mask,
                                       const QString &gateway, bool dnsManual, const QString &dns);
    // Пароль сохранённой Wi‑Fi — придёт в passwordReady.
    Q_INVOKABLE void requestPassword(const QString &uuid);
    Q_INVOKABLE void setPassword(const QString &uuid, const QString &password);
    Q_INVOKABLE void forget(const QString &uuid);
    Q_INVOKABLE void connectHidden(const QString &ssid, const QString &password);
    // file:// или путь; .conf — WireGuard, .ovpn — OpenVPN.
    Q_INVOKABLE void importVpn(const QString &file);
    Q_INVOKABLE void clearMessage();

Q_SIGNALS:
    void changed();
    void messageChanged();
    void passwordReady(const QString &uuid, const QString &password, const QString &error);
    // Изменение записано (или нет — error) — редактор закрывается или показывает ошибку.
    void saved(const QString &uuid, const QString &error);

private Q_SLOTS:
    void scheduleRebuild();
    void rebuild();

private:
    void setMessage(const QString &text, bool error);
    // inPlace — правка из раскрытой сети: итог только в saved(), без
    // общей строки сообщений (она сдвигала бы страницу).
    void watch(const QDBusPendingCall &call, const QString &uuid, const QString &failure, const QString &success = {},
               bool inPlace = false);
    static QString explain(const QString &dbusError);

    QTimer m_rebuild;
    bool m_available = false;
    bool m_wifiPresent = false;
    QVariantList m_devices;
    QVariantList m_connections;
    KeyedModel *m_deviceModel;
    KeyedModel *m_connectionModel;
    QString m_message;
    bool m_messageIsError = false;
};
