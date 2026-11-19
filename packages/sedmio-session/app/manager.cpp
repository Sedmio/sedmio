#include "manager.h"

#include <LayerShellQt/Window>

#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDebug>
#include <QFile>
#include <QGuiApplication>
#include <QProcess>
#include <QQmlComponent>
#include <QQmlContext>
#include <QScreen>
#include <QStandardPaths>

#include <climits>

namespace
{
const QString kLogind = QStringLiteral("org.freedesktop.login1");
const QString kLogindPath = QStringLiteral("/org/freedesktop/login1");
const QString kLogindManager = QStringLiteral("org.freedesktop.login1.Manager");

QDBusMessage systemdCall(const QString &method)
{
    return QDBusMessage::createMethodCall(QStringLiteral("org.freedesktop.systemd1"), QStringLiteral("/org/freedesktop/systemd1"),
                                          QStringLiteral("org.freedesktop.systemd1.Manager"), method);
}

// «yes», «challenge» (спросит пароль) — можно; «no», «na», нет ответа — нельзя.
bool allowed(const QString &answer)
{
    return answer == QLatin1String("yes") || answer == QLatin1String("challenge");
}
} // namespace

Manager::Manager(QObject *parent)
    : QObject(parent)
{
    // То, что экран спрашивает у ksmserver-logout-greeter (SedmioLogout.qml).
    QQmlContext *context = m_engine.rootContext();
    context->setContextProperty(QStringLiteral("manager"), this);
    context->setContextProperty(QStringLiteral("sedmioSession"), this);
    context->setContextProperty(QStringLiteral("ShutdownType"),
                                QVariantMap{
                                    {QStringLiteral("ShutdownTypeDefault"), int(Default)},
                                    {QStringLiteral("ShutdownTypeNone"), int(None)},
                                    {QStringLiteral("ShutdownTypeReboot"), int(Reboot)},
                                    {QStringLiteral("ShutdownTypeHalt"), int(Halt)},
                                    {QStringLiteral("ShutdownTypeLogout"), int(Logout)},
                                });
    context->setContextProperty(QStringLiteral("sdtype"), int(Default));
    context->setContextProperty(QStringLiteral("canLogout"), true);
    context->setContextProperty(QStringLiteral("softwareUpdatePending"), false);
    context->setContextProperty(QStringLiteral("maysd"), true);
    context->setContextProperty(QStringLiteral("spdMethods"), QVariantMap());
}

bool Manager::registerOnBus()
{
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.isConnected())
        return false;
    bus.registerObject(QStringLiteral("/LogoutPrompt"), new LogoutPrompt(this), QDBusConnection::ExportScriptableSlots);
    bus.registerObject(QStringLiteral("/Shutdown"), new Shutdown(this), QDBusConnection::ExportScriptableSlots);
    // Имя занято окном Plasma (его подняла шина, пока нас не было) — встаём
    // в очередь: оно закроется, имя перейдёт к нам.
    QDBusConnectionInterface *iface = bus.interface();
    bool ok = true;
    for (const QString &name : {QStringLiteral("org.kde.LogoutPrompt"), QStringLiteral("org.kde.Shutdown")}) {
        const auto reply = iface->registerService(name, QDBusConnectionInterface::QueueService, QDBusConnectionInterface::DontAllowReplacement);
        if (!reply.isValid()) {
            qWarning() << "sedmio-session-manager: не удалось занять" << name << reply.error().message();
            ok = false;
        }
    }
    return ok;
}

bool Manager::taskManagerAvailable() const
{
    return !QStandardPaths::findExecutable(QStringLiteral("sedmio-tasks")).isEmpty();
}

bool Manager::launchTaskManager()
{
    // В своей группе systemd (как из оболочки): перезапуск этой службы
    // не должен закрыть диспетчер задач.
    const QString launch = QStringLiteral("/usr/lib/sedmio/launch");
    if (QFile::exists(launch) && QProcess::startDetached(launch, {QStringLiteral("sedmio-tasks"), QStringLiteral("sedmio-tasks")}))
        return true;
    return QProcess::startDetached(QStringLiteral("sedmio-tasks"), {});
}

QString Manager::logind(const QString &method) const
{
    const QDBusMessage reply = QDBusConnection::systemBus().call(QDBusMessage::createMethodCall(kLogind, kLogindPath, kLogindManager, method), QDBus::Block, 3000);
    return reply.type() == QDBusMessage::ReplyMessage ? reply.arguments().value(0).toString() : QString();
}

void Manager::prompt(Type type)
{
    if (m_logoutType != None) {
        qWarning() << "sedmio-session-manager: выход уже идёт, экран не показываю";
        return;
    }
    if (!m_windows.isEmpty()) {
        // Уже открыт — только поднять (второй Ctrl+Alt+Del).
        for (const auto &window : std::as_const(m_windows)) {
            if (window)
                window->requestActivate();
        }
        return;
    }
    // Экран перечитывается с диска: обновили или починили файл — без
    // перезапуска службы (иначе движок помнит прошлую ошибку загрузки).
    m_engine.clearComponentCache();
    QQmlContext *context = m_engine.rootContext();
    context->setContextProperty(QStringLiteral("sdtype"), int(type));
    // Нет ответа logind — кнопки всё равно показываем: лучше отказ при
    // нажатии, чем экран без «Выключить».
    const QString powerOff = logind(QStringLiteral("CanPowerOff"));
    context->setContextProperty(QStringLiteral("maysd"), powerOff.isEmpty() || allowed(powerOff));
    context->setContextProperty(QStringLiteral("spdMethods"),
                                QVariantMap{
                                    {QStringLiteral("SuspendState"), allowed(logind(QStringLiteral("CanSuspend")))},
                                    {QStringLiteral("HibernateState"), false},
                                    {QStringLiteral("HybridSuspendState"), false},
                                });

    const auto screens = QGuiApplication::screens();
    for (QScreen *screen : screens)
        showOn(screen);
}

void Manager::showOn(QScreen *screen)
{
    QQmlComponent component(&m_engine, QUrl(QStringLiteral("qrc:/qt/qml/Sedmio/Session/LogoutWindow.qml")));
    QObject *object = component.create();
    auto *window = qobject_cast<QQuickWindow *>(object);
    if (!window) {
        qWarning() << "sedmio-session-manager: окно не создалось" << component.errors();
        delete object;
        return;
    }
    const bool main = screen == QGuiApplication::primaryScreen() || m_windows.isEmpty();
    window->setScreen(screen);
    window->setGeometry(screen->geometry());
    if (auto *layer = LayerShellQt::Window::get(window)) {
        layer->setLayer(LayerShellQt::Window::LayerOverlay);
        layer->setAnchors(LayerShellQt::Window::Anchors(LayerShellQt::Window::AnchorTop | LayerShellQt::Window::AnchorBottom
                                                        | LayerShellQt::Window::AnchorLeft | LayerShellQt::Window::AnchorRight));
        layer->setExclusiveZone(-1);
        layer->setScope(QStringLiteral("sedmio-logout"));
        layer->setScreen(screen);
        // Клавиатура — у экрана на главном мониторе; на остальных — мышь.
        layer->setKeyboardInteractivity(main ? LayerShellQt::Window::KeyboardInteractivityExclusive
                                             : LayerShellQt::Window::KeyboardInteractivityNone);
    }
    // Монитор отключили — окно закрывается; убрать его из списка.
    connect(screen, &QObject::destroyed, window, &QObject::deleteLater);
    window->show();
    if (main)
        window->requestActivate();
    m_windows.append(window);
}

void Manager::closePrompt()
{
    for (const auto &window : std::as_const(m_windows)) {
        if (window) {
            window->hide();
            window->deleteLater();
        }
    }
    m_windows.clear();
}

void Manager::cancelRequested()
{
    closePrompt();
}

void Manager::lockScreenRequested()
{
    closePrompt();
    // Блокирует KWin (kscreenlocker).
    QDBusConnection::sessionBus().asyncCall(QDBusMessage::createMethodCall(QStringLiteral("org.freedesktop.ScreenSaver"), QStringLiteral("/ScreenSaver"),
                                                                           QStringLiteral("org.freedesktop.ScreenSaver"), QStringLiteral("Lock")));
}

void Manager::suspendRequested(int)
{
    closePrompt();
    QDBusMessage message = QDBusMessage::createMethodCall(kLogind, kLogindPath, kLogindManager, QStringLiteral("Suspend"));
    message << true;
    QDBusConnection::systemBus().asyncCall(message);
}

void Manager::logoutRequested()
{
    startLogout(Logout);
}

void Manager::haltRequested()
{
    startLogout(Halt);
}

void Manager::rebootRequested()
{
    startLogout(Reboot);
}

void Manager::startLogout(Type type)
{
    closePrompt();
    // Второй запрос, пока первый идёт (два нажатия), — не дублировать.
    if (m_logoutType != None) {
        qWarning() << "sedmio-session-manager: выход уже идёт";
        return;
    }
    m_logoutType = type;

    // KWin закрывает окна; программа с несохранённым может спросить и
    // отменить выход — тогда false. Ждём сколько угодно: человек думает.
    QDBusMessage message = QDBusMessage::createMethodCall(QStringLiteral("org.kde.KWin"), QStringLiteral("/Session"), QStringLiteral("org.kde.KWin.Session"),
                                                          QStringLiteral("closeWaylandWindows"));
    auto *watcher = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(message, INT_MAX), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *watcher) {
        watcher->deleteLater();
        QDBusPendingReply<bool> reply = *watcher;
        if (reply.isError()) {
            // KWin нет на шине — закрывать нечего, выходим. Другая ошибка
            // (KWin не смог) — как у Plasma: отмена, лучше остаться в сеансе.
            if (reply.error().type() != QDBusError::ServiceUnknown) {
                qWarning() << "sedmio-session-manager: KWin не закрыл окна:" << reply.error().message();
                cancelled();
                return;
            }
        } else if (!reply.value()) {
            cancelled();
            return;
        }
        finish();
    });
}

void Manager::cancelled()
{
    m_logoutType = None;
}

void Manager::finish()
{
    auto stopSession = [] {
        // sedmio-session ждёт конца своей цели; она привязана к
        // graphical-session.target — как у Plasma.
        QDBusMessage stop = systemdCall(QStringLiteral("StopUnit"));
        stop << QStringLiteral("graphical-session.target") << QStringLiteral("fail");
        QDBusConnection::sessionBus().call(stop, QDBus::Block, 10000);
    };
    if (m_logoutType == Logout) {
        stopSession();
        return;
    }
    // Выключение и перезагрузка — logind; сеанс он закроет сам. Нужен
    // пароль (другие пользователи вошли) — спросит агент polkit (окна уже
    // закрыты, а сеанс ещё жив). Отказ — хотя бы выйти из сеанса: окна
    // всё равно закрыты, а с экрана входа можно выключить.
    QDBusMessage message = QDBusMessage::createMethodCall(kLogind, kLogindPath, kLogindManager,
                                                          m_logoutType == Reboot ? QStringLiteral("Reboot") : QStringLiteral("PowerOff"));
    message << true;
    auto *watcher = new QDBusPendingCallWatcher(QDBusConnection::systemBus().asyncCall(message, 120000), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [stopSession](QDBusPendingCallWatcher *watcher) {
        watcher->deleteLater();
        if (watcher->isError()) {
            qWarning() << "sedmio-session-manager: logind отказал:" << watcher->error().message();
            stopSession();
        }
    });
}

LogoutPrompt::LogoutPrompt(Manager *manager)
    : QObject(manager)
    , m_manager(manager)
{
}

void LogoutPrompt::promptLogout()
{
    m_manager->prompt(Manager::Logout);
}

void LogoutPrompt::promptShutDown()
{
    m_manager->prompt(Manager::Halt);
}

void LogoutPrompt::promptReboot()
{
    m_manager->prompt(Manager::Reboot);
}

void LogoutPrompt::promptAll()
{
    m_manager->prompt(Manager::Default);
}

Shutdown::Shutdown(Manager *manager)
    : QObject(manager)
    , m_manager(manager)
{
}

void Shutdown::logout()
{
    m_manager->startLogout(Manager::Logout);
}

void Shutdown::logoutAndShutdown()
{
    m_manager->startLogout(Manager::Halt);
}

void Shutdown::logoutAndReboot()
{
    m_manager->startLogout(Manager::Reboot);
}

void Shutdown::saveSession()
{
}
