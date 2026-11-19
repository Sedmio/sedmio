// sedmio-session-manager: выход, выключение и перезагрузка в сеансе
// Sedmio — вместо ksmserver, plasma-shutdown и ksmserver-logout-greeter.
// См. manager.h. Запускает sedmio-session-manager.service.

#include "manager.h"

#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDBusServiceWatcher>
#include <QGuiApplication>
#include <QTimer>

namespace
{
// Заставка входа (ksplashqml) закрывается, когда соберёт все этапы. Этапы
// «startPlasma» и «ksmserver» слали startplasma и ksmserver, которых у нас
// нет, — шлём сами («desktop» шлёт оболочка). Заставка может появиться на
// шине позже нас — тогда как только появится.
void feedSplash(QObject *parent)
{
    auto send = [] {
        for (const QString &stage : {QStringLiteral("startPlasma"), QStringLiteral("ksmserver")}) {
            QDBusMessage message =
                QDBusMessage::createMethodCall(QStringLiteral("org.kde.KSplash"), QStringLiteral("/KSplash"), QStringLiteral("org.kde.KSplash"), QStringLiteral("setStage"));
            message << stage;
            QDBusConnection::sessionBus().call(message, QDBus::NoBlock);
        }
    };
    auto *watcher = new QDBusServiceWatcher(QStringLiteral("org.kde.KSplash"), QDBusConnection::sessionBus(), QDBusServiceWatcher::WatchForRegistration, parent);
    QObject::connect(watcher, &QDBusServiceWatcher::serviceRegistered, parent, send);
    if (QDBusConnection::sessionBus().interface()->isServiceRegistered(QStringLiteral("org.kde.KSplash")))
        send();
    // Заставка живёт не дольше 40 с (plasma-ksplash.service) — дальше не ждём.
    QTimer::singleShot(60000, watcher, &QObject::deleteLater);
}
} // namespace

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("sedmio-session-manager"));
    app.setOrganizationName(QStringLiteral("sedmio"));
    // Экран выхода закрывается — программа остаётся.
    app.setQuitOnLastWindowClosed(false);

    Manager manager;
    if (!manager.registerOnBus())
        return 1;
    feedSplash(&app);
    return app.exec();
}
