#include "storehost.h"

#include <KWindowSystem>

#include <QDBusConnection>
#include <QDBusMessage>
#include <QProcess>

namespace
{
const QString storeService = QStringLiteral("org.sedmio.Store");
const QString storePath = QStringLiteral("/org/sedmio/Store");
}

StoreHost::StoreHost(QObject *parent)
    : QObject(parent)
{
}

StoreHost *StoreHost::instance()
{
    static StoreHost *host = new StoreHost;
    QJSEngine::setObjectOwnership(host, QJSEngine::CppOwnership);
    return host;
}

bool StoreHost::registerOnBus()
{
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.isConnected())
        return true;
    if (!bus.registerService(storeService))
        return false;
    new StoreAdaptor(this);
    bus.registerObject(storePath, this);
    return true;
}

bool StoreHost::forward(const QString &appId)
{
    QDBusMessage message = QDBusMessage::createMethodCall(storeService, storePath, storeService, QStringLiteral("Show"));
    message << qEnvironmentVariable("XDG_ACTIVATION_TOKEN") << appId;
    const QDBusMessage reply = QDBusConnection::sessionBus().call(message, QDBus::Block, 3000);
    return reply.type() == QDBusMessage::ReplyMessage;
}

QString StoreHost::takeStartApp()
{
    return std::exchange(m_startApp, QString());
}

void StoreHost::show(const QString &token, const QString &appId)
{
    if (!m_window)
        return;
    m_window->show();
    if (m_window->windowState() & Qt::WindowMinimized)
        m_window->showNormal();
    if (!token.isEmpty())
        KWindowSystem::setCurrentXdgActivationToken(token);
    KWindowSystem::activateWindow(m_window);
    if (!appId.isEmpty())
        Q_EMIT openApp(appId);
}

void StoreHost::openSystemUpdates()
{
    QProcess::startDetached(QStringLiteral("/usr/lib/sedmio/launch"),
                            {QStringLiteral("sedmio-preferences"), QStringLiteral("sedmio-preferences"), QStringLiteral("updates")});
}
