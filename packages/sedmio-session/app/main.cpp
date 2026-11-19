// sedmio-session-manager: выход, выключение и перезагрузка в сеансе
// Sedmio — вместо ksmserver, plasma-shutdown и ksmserver-logout-greeter
// (см. manager.h), и аварийный режим без оболочки (см. shellwatch.h).
// Запускает sedmio-session-manager.service.

#include "manager.h"
#include "shellwatch.h"

#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDBusServiceWatcher>
#include <QGuiApplication>
#include <QTimer>

namespace
{
// Заставка входа (sedmio-splash, на шине — как ksplash) закрывается, когда
// соберёт все этапы. «startPlasma» и «ksmserver» шлём мы («desktop» —
// оболочка). Заставка может появиться на шине позже нас — тогда как
// только появится.
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
    // Заставка живёт не дольше 30 с — дальше не ждём.
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
    // Оболочка упала насовсем — плашка с перезапуском (аварийный режим).
    ShellWatch shellWatch;
    return app.exec();
}
