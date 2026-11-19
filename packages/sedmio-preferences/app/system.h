#pragma once

#include <QDateTime>
#include <QObject>
#include <QVariantList>

#include <functional>
#include <QtQml/qqmlregistration.h>

// «Дата и время» и «О системе»: часовой пояс и синхронизация времени
// (systemd-timedated), имя компьютера (systemd-hostnamed), сведения о
// системе и железе. Что требует прав, спрашивает пароль через polkit —
// окно пароля показывает оболочка.
class SystemInfo : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(QString timeZone READ timeZone NOTIFY changed)
    Q_PROPERTY(QString timeZoneLabel READ timeZoneLabel NOTIFY changed)
    Q_PROPERTY(bool ntp READ ntp NOTIFY changed)
    Q_PROPERTY(bool canNtp READ canNtp NOTIFY changed)
    Q_PROPERTY(QString hostname READ hostname NOTIFY changed)
    Q_PROPERTY(QString error READ error NOTIFY changed)

    Q_PROPERTY(QString osName READ osName CONSTANT)
    Q_PROPERTY(QString kernel READ kernel CONSTANT)
    Q_PROPERTY(QString cpu READ cpu CONSTANT)
    Q_PROPERTY(QString memory READ memory CONSTANT)
    Q_PROPERTY(QString gpu READ gpu CONSTANT)
    Q_PROPERTY(QString disk READ disk CONSTANT)

public:
    explicit SystemInfo(QObject *parent = nullptr);

    QString timeZone() const { return m_timeZone; }
    QString timeZoneLabel() const;
    bool ntp() const { return m_ntp; }
    bool canNtp() const { return m_canNtp; }
    QString hostname() const { return m_hostname; }
    QString error() const { return m_error; }

    QString osName() const;
    QString kernel() const;
    QString cpu() const;
    QString memory() const;
    QString gpu() const;
    QString disk() const;

    // Время и дата в выбранном поясе. Не местное время процесса: оно
    // запоминает пояс при запуске и о смене не узнаёт.
    // moment — сейчас (из QML: new Date() раз в секунду).
    Q_INVOKABLE QString timeText(const QDateTime &moment) const;
    Q_INVOKABLE QString dateText(const QDateTime &moment) const;

    // [{id, label, search}] — все пояса «Регион/Город», по смещению.
    Q_INVOKABLE QVariantList timeZones() const;
    Q_INVOKABLE void setTimeZone(const QString &id);
    Q_INVOKABLE void setNtp(bool enabled);
    Q_INVOKABLE void setHostname(const QString &name);
    // Подходит ли имя компьютера: латиница, цифры, дефис, до 63 знаков.
    Q_INVOKABLE bool validHostname(const QString &name) const;

Q_SIGNALS:
    void changed();

private Q_SLOTS:
    void onPropertiesChanged(const QString &interface, const QVariantMap &changed, const QStringList &invalidated);

private:
    void load();
    void call(const QString &service, const QString &path, const QString &interface, const QString &method,
              const QVariantList &args, std::function<void()> done = {});

    QString m_timeZone;
    bool m_ntp = false;
    bool m_canNtp = false;
    QString m_hostname;
    QString m_error;
};

// Пояс для подписи: «Москва, стандартное время (UTC+03:00)».
QString timeZoneLabel(const QString &id);
