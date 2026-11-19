#include "sessionmanagement.h"

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QHash>
#include <QMutex>

namespace
{
const QString kLogind = QStringLiteral("org.freedesktop.login1");
const QString kLogindPath = QStringLiteral("/org/freedesktop/login1");
const QString kLogindManager = QStringLiteral("org.freedesktop.login1.Manager");

// Ответ logind на CanSuspend и т. п. За время работы не меняется (кроме
// гибернации после смены swap — тогда перезапуск службы), поэтому один
// раз на процесс: SessionManagement создают и на каждое нажатие кнопки.
bool logindCan(const QString &method)
{
    static QMutex mutex;
    static QHash<QString, bool> cache;
    QMutexLocker locker(&mutex);
    const auto it = cache.constFind(method);
    if (it != cache.constEnd())
        return *it;
    const QDBusMessage reply =
        QDBusConnection::systemBus().call(QDBusMessage::createMethodCall(kLogind, kLogindPath, kLogindManager, method), QDBus::Block, 3000);
    if (reply.type() != QDBusMessage::ReplyMessage)
        return false; // нет ответа — спросим снова в следующий раз
    const QString answer = reply.arguments().value(0).toString();
    // «challenge» — можно, спросит пароль.
    const bool can = answer == QLatin1String("yes") || answer == QLatin1String("challenge");
    cache.insert(method, can);
    return can;
}

void logindCall(const QString &method)
{
    QDBusMessage message = QDBusMessage::createMethodCall(kLogind, kLogindPath, kLogindManager, method);
    message << true; // interactive: polkit может спросить пароль
    QDBusConnection::systemBus().asyncCall(message);
}

void sessionCall(const QString &service, const QString &path, const QString &interface, const QString &method)
{
    QDBusConnection::sessionBus().asyncCall(QDBusMessage::createMethodCall(service, path, interface, method));
}

// org.kde.Shutdown на шине только пока идёт выход (по нему powerdevil и
// не усыпляет) — постоянное имя sedmio-session-manager.
void shutdownCall(const QString &method)
{
    sessionCall(QStringLiteral("org.sedmio.SessionManager"), QStringLiteral("/Shutdown"), QStringLiteral("org.kde.Shutdown"), method);
}

void promptCall(const QString &method)
{
    sessionCall(QStringLiteral("org.kde.LogoutPrompt"), QStringLiteral("/LogoutPrompt"), QStringLiteral("org.kde.LogoutPrompt"), method);
}
} // namespace

SessionManagement::SessionManagement(QObject *parent)
    : QObject(parent)
{
}

SessionManagement::State SessionManagement::state() const
{
    return State::Ready;
}

bool SessionManagement::canShutdown() const
{
    return logindCan(QStringLiteral("CanPowerOff"));
}

bool SessionManagement::canReboot() const
{
    return logindCan(QStringLiteral("CanReboot"));
}

bool SessionManagement::canLogout() const
{
    return true;
}

bool SessionManagement::canSuspend() const
{
    return logindCan(QStringLiteral("CanSuspend"));
}

bool SessionManagement::canHybridSuspend() const
{
    return logindCan(QStringLiteral("CanHybridSleep"));
}

bool SessionManagement::canHibernate() const
{
    return logindCan(QStringLiteral("CanHibernate"));
}

bool SessionManagement::canSuspendThenHibernate() const
{
    return logindCan(QStringLiteral("CanSuspendThenHibernate"));
}

bool SessionManagement::canSwitchUser() const
{
    return false;
}

bool SessionManagement::canLock() const
{
    return true;
}

bool SessionManagement::canSaveSession() const
{
    return false;
}

// Подтверждение: Skip — сразу; иначе — экран «Что сделать?» с этим
// действием по умолчанию (как в Plasma).
void SessionManagement::requestShutdown(ConfirmationMode mode)
{
    if (mode == ConfirmationMode::Skip)
        shutdownCall(QStringLiteral("logoutAndShutdown"));
    else
        promptCall(QStringLiteral("promptShutDown"));
}

void SessionManagement::requestReboot(ConfirmationMode mode)
{
    if (mode == ConfirmationMode::Skip)
        shutdownCall(QStringLiteral("logoutAndReboot"));
    else
        promptCall(QStringLiteral("promptReboot"));
}

void SessionManagement::requestLogout(ConfirmationMode mode)
{
    if (mode == ConfirmationMode::Skip)
        shutdownCall(QStringLiteral("logout"));
    else
        promptCall(QStringLiteral("promptLogout"));
}

void SessionManagement::requestLogoutPrompt()
{
    promptCall(QStringLiteral("promptAll"));
}

void SessionManagement::suspend()
{
    if (canSuspend())
        logindCall(QStringLiteral("Suspend"));
}

void SessionManagement::hybridSuspend()
{
    if (canHybridSuspend())
        logindCall(QStringLiteral("HybridSleep"));
}

void SessionManagement::hibernate()
{
    if (canHibernate())
        logindCall(QStringLiteral("Hibernate"));
}

void SessionManagement::suspendThenHibernate()
{
    if (canSuspendThenHibernate())
        logindCall(QStringLiteral("SuspendThenHibernate"));
}

void SessionManagement::switchUser()
{
}

void SessionManagement::lock()
{
    sessionCall(QStringLiteral("org.freedesktop.ScreenSaver"), QStringLiteral("/ScreenSaver"), QStringLiteral("org.freedesktop.ScreenSaver"), QStringLiteral("Lock"));
}

void SessionManagement::saveSession()
{
}
