#include "app.h"

#include <KWindowSystem>

#include <QDBusConnection>
#include <QDBusMessage>
#include <QProcess>

namespace
{
const QString service = QStringLiteral("org.sedmio.Preferences");
const QString path = QStringLiteral("/org/sedmio/Preferences");
const QStringList pages = {QStringLiteral("display"), QStringLiteral("wallpaper"), QStringLiteral("mouse"), QStringLiteral("keyboard"),
                           QStringLiteral("sound"), QStringLiteral("power"), QStringLiteral("defaults"), QStringLiteral("datetime"), QStringLiteral("about")};
} // namespace

App::App(QObject *parent)
    : QObject(parent)
{
}

QString App::normalizePage(const QString &page)
{
    // Имена разделов KDE тоже понимаем: так можно подставить нас вместо них.
    static const QHash<QString, QString> aliases = {
        {QStringLiteral("kcm_kscreen"), QStringLiteral("display")},
        {QStringLiteral("screen"), QStringLiteral("display")},
        {QStringLiteral("kcm_wallpaper"), QStringLiteral("wallpaper")},
        {QStringLiteral("kcm_mouse"), QStringLiteral("mouse")},
        {QStringLiteral("kcm_touchpad"), QStringLiteral("mouse")},
        {QStringLiteral("kcm_keyboard"), QStringLiteral("keyboard")},
        {QStringLiteral("kcm_pulseaudio"), QStringLiteral("sound")},
        {QStringLiteral("audio"), QStringLiteral("sound")},
        {QStringLiteral("kcm_powerdevilprofilesconfig"), QStringLiteral("power")},
        {QStringLiteral("kcm_componentchooser"), QStringLiteral("defaults")},
        {QStringLiteral("kcm_clock"), QStringLiteral("datetime")},
        {QStringLiteral("kcm_about-distro"), QStringLiteral("about")},
    };
    const QString lower = page.toLower();
    if (pages.contains(lower))
        return lower;
    return aliases.value(lower);
}

void App::setPage(const QString &page)
{
    const QString normalized = normalizePage(page);
    if (normalized.isEmpty() || normalized == m_page)
        return;
    m_page = normalized;
    Q_EMIT pageChanged();
}

bool App::registerOnBus()
{
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.isConnected())
        return true;
    if (!bus.registerService(service))
        return false;
    new PreferencesAdaptor(this);
    bus.registerObject(path, this);
    return true;
}

bool App::forward(const QString &page)
{
    QDBusMessage message = QDBusMessage::createMethodCall(service, path, service, QStringLiteral("Show"));
    message << page << qEnvironmentVariable("XDG_ACTIVATION_TOKEN");
    const QDBusMessage reply = QDBusConnection::sessionBus().call(message, QDBus::Block, 5000);
    return reply.type() == QDBusMessage::ReplyMessage;
}

void App::show(const QString &page, const QString &token)
{
    if (!page.isEmpty())
        setPage(page);
    if (!m_window)
        return;
    m_window->show();
    if (m_window->windowState() & Qt::WindowMinimized)
        m_window->showNormal();
    if (!token.isEmpty())
        KWindowSystem::setCurrentXdgActivationToken(token);
    KWindowSystem::activateWindow(m_window);
}

void App::openKde(const QString &module)
{
    QStringList args;
    if (!module.isEmpty())
        args << module;
    QProcess::startDetached(QStringLiteral("systemsettings"), args);
}
