#include "shellwatch.h"

#include <LayerShellQt/Window>

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusVariant>
#include <QDebug>
#include <QGuiApplication>
#include <QQmlComponent>
#include <QQmlContext>
#include <QScreen>

namespace
{
const QString kSystemd = QStringLiteral("org.freedesktop.systemd1");
const QString kUnitInterface = QStringLiteral("org.freedesktop.systemd1.Unit");
const QString kShellUnit = QStringLiteral("sedmio-shell.service");

QDBusMessage managerCall(const QString &method, const QVariantList &args = {})
{
    QDBusMessage message = QDBusMessage::createMethodCall(kSystemd, QStringLiteral("/org/freedesktop/systemd1"), QStringLiteral("org.freedesktop.systemd1.Manager"), method);
    message.setArguments(args);
    return message;
}
} // namespace

ShellWatch::ShellWatch(QObject *parent)
    : QObject(parent)
{
    m_engine.rootContext()->setContextProperty(QStringLiteral("shellWatch"), this);
    // Каждое падение systemd на миг отмечает «failed», даже если сразу
    // перезапустит (RestartSec — 0,1 с). Насовсем — если «failed» и через
    // пару секунд.
    m_confirm.setSingleShot(true);
    m_confirm.setInterval(2000);
    connect(&m_confirm, &QTimer::timeout, this, [this] {
        if (m_failed || !currentlyFailed())
            return;
        m_failed = true;
        qWarning() << "sedmio-session-manager: оболочка не запустилась — аварийный режим";
        showBanner();
    });
    // Главный монитор сменился (отключили) — плашка переезжает.
    connect(qGuiApp, &QGuiApplication::primaryScreenChanged, this, [this] {
        if (m_banner)
            showBanner();
    });
    watch();
}

void ShellWatch::watch()
{
    QDBusConnection bus = QDBusConnection::sessionBus();
    // Без подписки systemd не шлёт изменения состояния служб.
    bus.call(managerCall(QStringLiteral("Subscribe")), QDBus::Block, 3000);
    const QDBusMessage reply = bus.call(managerCall(QStringLiteral("LoadUnit"), {kShellUnit}), QDBus::Block, 3000);
    if (reply.type() != QDBusMessage::ReplyMessage) {
        qWarning() << "sedmio-session-manager: не нашёл" << kShellUnit << reply.errorMessage();
        return;
    }
    m_unitPath = reply.arguments().value(0).value<QDBusObjectPath>().path();
    bus.connect(kSystemd, m_unitPath, QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("PropertiesChanged"), this,
                SLOT(propertiesChanged(QString, QVariantMap, QStringList)));
    // Оболочка могла упасть ещё до нас (мы перезапустились).
    update(currentlyFailed());
}

bool ShellWatch::isFailed(const QString &activeState, const QString &subState)
{
    // Упала и ждёт перезапуска (auto-restart) — ещё не беда.
    return activeState == QLatin1String("failed") && subState != QLatin1String("auto-restart");
}

bool ShellWatch::currentlyFailed() const
{
    auto get = [this](const QString &property) {
        QDBusMessage message = QDBusMessage::createMethodCall(kSystemd, m_unitPath, QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("Get"));
        message << kUnitInterface << property;
        const QDBusMessage reply = QDBusConnection::sessionBus().call(message, QDBus::Block, 3000);
        return reply.arguments().value(0).value<QDBusVariant>().variant().toString();
    };
    return isFailed(get(QStringLiteral("ActiveState")), get(QStringLiteral("SubState")));
}

void ShellWatch::propertiesChanged(const QString &interface, const QVariantMap &changed, const QStringList &)
{
    if (interface != kUnitInterface)
        return;
    if (changed.contains(QStringLiteral("ActiveState")) && changed.contains(QStringLiteral("SubState")))
        update(isFailed(changed.value(QStringLiteral("ActiveState")).toString(), changed.value(QStringLiteral("SubState")).toString()));
    else
        update(currentlyFailed());
}

void ShellWatch::update(bool failed)
{
    if (failed) {
        // Плашку покажет m_confirm, если не перезапустится.
        if (!m_failed && !m_confirm.isActive())
            m_confirm.start();
        return;
    }
    m_confirm.stop();
    if (m_failed) {
        m_failed = false;
        hideBanner();
    }
}

void ShellWatch::restart()
{
    hideBanner();
    // Счётчик перезапусков исчерпан — сначала сбросить, иначе systemd откажет.
    QDBusConnection bus = QDBusConnection::sessionBus();
    bus.call(managerCall(QStringLiteral("ResetFailedUnit"), {kShellUnit}), QDBus::NoBlock);
    bus.call(managerCall(QStringLiteral("StartUnit"), {kShellUnit, QStringLiteral("replace")}), QDBus::NoBlock);
}

void ShellWatch::dismiss()
{
    hideBanner();
}

void ShellWatch::showBanner()
{
    hideBanner();
    QScreen *screen = QGuiApplication::primaryScreen();
    if (!screen)
        return;
    QQmlComponent component(&m_engine, QUrl(QStringLiteral("qrc:/qt/qml/Sedmio/Session/ShellBanner.qml")));
    QObject *object = component.create();
    auto *window = qobject_cast<QQuickWindow *>(object);
    if (!window) {
        qWarning() << "sedmio-session-manager: плашка не создалась" << component.errors();
        delete object;
        return;
    }
    window->setScreen(screen);
    window->resize(screen->geometry().width(), window->height());
    if (auto *layer = LayerShellQt::Window::get(window)) {
        layer->setLayer(LayerShellQt::Window::LayerTop);
        layer->setAnchors(LayerShellQt::Window::Anchors(LayerShellQt::Window::AnchorTop | LayerShellQt::Window::AnchorLeft | LayerShellQt::Window::AnchorRight));
        // Окна не заходят под плашку.
        layer->setExclusiveZone(window->height());
        layer->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityNone);
        layer->setScope(QStringLiteral("sedmio-shell-banner"));
        layer->setScreen(screen);
    }
    connect(screen, &QObject::destroyed, window, &QObject::deleteLater);
    window->show();
    m_banner = window;
}

void ShellWatch::hideBanner()
{
    if (m_banner) {
        m_banner->hide();
        m_banner->deleteLater();
    }
    m_banner = nullptr;
}
