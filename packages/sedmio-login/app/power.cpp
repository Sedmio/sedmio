#include "power.h"

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCall>

namespace
{
QDBusMessage logind(const QString &method)
{
    return QDBusMessage::createMethodCall(QStringLiteral("org.freedesktop.login1"), QStringLiteral("/org/freedesktop/login1"),
                                          QStringLiteral("org.freedesktop.login1.Manager"), method);
}
} // namespace

Power::Power(QObject *parent)
    : QObject(parent)
{
    const QDBusMessage reply = QDBusConnection::systemBus().call(logind(QStringLiteral("CanSuspend")), QDBus::Block, 2000);
    const QString answer = reply.arguments().value(0).toString();
    m_canSuspend = answer == QLatin1String("yes") || answer == QLatin1String("challenge");
}

bool Power::canSuspend() const
{
    return m_canSuspend;
}

void Power::suspend()
{
    QDBusMessage message = logind(QStringLiteral("Suspend"));
    message << true;
    QDBusConnection::systemBus().asyncCall(message);
}
