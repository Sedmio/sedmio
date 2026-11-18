#include "app.h"

#include <KWindowSystem>

#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDir>
#include <QFileInfo>
#include <QGuiApplication>
#include <QJSEngine>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QQuickWindow>
#include <QTimer>

namespace
{
App *s_instance = nullptr;

// Своё имя — чтобы найти именно запущенные «Файлы», а не того, кто ещё
// держит org.freedesktop.FileManager1 (пока стоит Dolphin, он тоже его берёт).
const QString ownService = QStringLiteral("org.sedmio.Files");
const QString fm1Service = QStringLiteral("org.freedesktop.FileManager1");
const QString fm1Path = QStringLiteral("/org/freedesktop/FileManager1");

QUrl toUrl(const QString &uri)
{
    return QUrl::fromUserInput(uri, QDir::currentPath(), QUrl::AssumeLocalFile)
        .adjusted(QUrl::StripTrailingSlash | QUrl::NormalizePathSegments);
}
} // namespace

App::App(QQmlEngine *engine)
    : QObject(engine)
    , m_engine(engine)
{
    s_instance = this;
    // Закрываемся сами: когда нет ни окон, ни заданий (см. maybeQuit).
    QGuiApplication::setQuitOnLastWindowClosed(false);

    connect(qGuiApp, &QGuiApplication::focusWindowChanged, this, [this](QWindow *window) {
        // Окна вопросов и меню — не «рабочие» окна.
        if (window && m_windows.contains(window) && m_lastWindow != window) {
            m_lastWindow = window;
            Q_EMIT lastWindowChanged();
        }
    });
}

App::~App()
{
    s_instance = nullptr;
}

App *App::instance()
{
    return s_instance;
}

App *App::create(QQmlEngine *, QJSEngine *)
{
    QJSEngine::setObjectOwnership(s_instance, QJSEngine::CppOwnership);
    return s_instance;
}

bool App::registerOnBus()
{
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.isConnected())
        return true; // без шины — просто программа с окнами
    if (!bus.registerService(ownService))
        return false;

    new FileManager1Adaptor(this);
    bus.registerObject(fm1Path, this);
    bus.registerService(fm1Service); // занято Dolphin — не страшно, есть своё имя
    return true;
}

bool App::forward(const QString &method, const QStringList &uris)
{
    QDBusMessage message = QDBusMessage::createMethodCall(ownService, fm1Path, fm1Service, method);
    message << uris << qEnvironmentVariable("XDG_ACTIVATION_TOKEN");
    const QDBusMessage reply = QDBusConnection::sessionBus().call(message, QDBus::Block, 5000);
    return reply.type() == QDBusMessage::ReplyMessage;
}

void App::openWindow(const QUrl &folder, const QList<QUrl> &select, const QString &token)
{
    QQmlComponent component(m_engine, QStringLiteral("Sedmio.Files"), QStringLiteral("Main"));
    QObject *object = component.createWithInitialProperties({
        {QStringLiteral("startUrl"), folder.isEmpty() ? QUrl::fromLocalFile(QDir::homePath()) : folder},
        {QStringLiteral("selectUrls"), QVariant::fromValue(select)},
    });
    auto *window = qobject_cast<QQuickWindow *>(object);
    if (!window) {
        qWarning() << component.errorString();
        delete object;
        maybeQuit();
        return;
    }
    QQmlEngine::setObjectOwnership(window, QQmlEngine::CppOwnership);
    m_windows.append(window);
    m_lastWindow = window;
    Q_EMIT lastWindowChanged();

    // Закрыли окно — удаляем его совсем (свёрнутое остаётся visible).
    connect(window, &QWindow::visibleChanged, this, [this, window](bool visible) {
        if (visible)
            return;
        m_windows.removeAll(window);
        if (m_lastWindow == window) {
            m_lastWindow = m_windows.isEmpty() ? nullptr : m_windows.constLast();
            Q_EMIT lastWindowChanged();
        }
        window->deleteLater();
        QTimer::singleShot(0, this, &App::maybeQuit);
    });

    // Пришли по просьбе другой программы — поднять окно над ней (токен
    // активации Wayland от той программы, иначе KWin не даст фокус).
    if (!token.isEmpty())
        KWindowSystem::setCurrentXdgActivationToken(token);
    KWindowSystem::activateWindow(window);
}

void App::showFolders(const QStringList &uris, const QString &token)
{
    if (uris.isEmpty()) {
        openWindow({}, {}, token);
        return;
    }
    for (const QString &uri : uris)
        openWindow(toUrl(uri), {}, token);
}

void App::showItems(const QStringList &uris, const QString &token)
{
    // По окну на папку, в нём выделено всё, что из неё просили показать.
    QList<QUrl> folders;
    QHash<QUrl, QList<QUrl>> items;
    for (const QString &uri : uris) {
        const QUrl url = toUrl(uri);
        QUrl parent = url.adjusted(QUrl::RemoveFilename | QUrl::StripTrailingSlash);
        if (parent.path().isEmpty())
            parent.setPath(QStringLiteral("/"));
        if (!items.contains(parent))
            folders.append(parent);
        items[parent].append(url);
    }
    for (const QUrl &folder : std::as_const(folders))
        openWindow(folder, items.value(folder), token);
}

void App::showProperties(const QList<QUrl> &urls, const QString &token)
{
    if (urls.isEmpty())
        return;
    QQmlComponent component(m_engine, QStringLiteral("Sedmio.Files"), QStringLiteral("PropertiesWindow"));
    QObject *object = component.createWithInitialProperties({
        {QStringLiteral("urls"), QVariant::fromValue(urls)},
    });
    auto *window = qobject_cast<QQuickWindow *>(object);
    if (!window) {
        qWarning() << component.errorString();
        delete object;
        maybeQuit();
        return;
    }
    QQmlEngine::setObjectOwnership(window, QQmlEngine::CppOwnership);
    window->setTransientParent(m_lastWindow);
    m_dialogs.append(window);
    connect(window, &QWindow::visibleChanged, this, [this, window](bool visible) {
        if (visible)
            return;
        m_dialogs.removeAll(window);
        window->deleteLater();
        QTimer::singleShot(0, this, &App::maybeQuit);
    });
    window->show();
    if (!token.isEmpty())
        KWindowSystem::setCurrentXdgActivationToken(token);
    KWindowSystem::activateWindow(window);
}

void App::showItemProperties(const QStringList &uris, const QString &token)
{
    QList<QUrl> urls;
    for (const QString &uri : uris)
        urls.append(toUrl(uri));
    if (urls.isEmpty())
        maybeQuit();
    else
        showProperties(urls, token);
}

void App::jobStarted()
{
    ++m_jobs;
}

void App::jobFinished()
{
    --m_jobs;
    QTimer::singleShot(0, this, &App::maybeQuit);
}

void App::maybeQuit()
{
    if (m_windows.isEmpty() && m_dialogs.isEmpty() && m_jobs <= 0)
        QCoreApplication::quit();
}

FileManager1Adaptor::FileManager1Adaptor(App *app)
    : QDBusAbstractAdaptor(app)
    , m_app(app)
{
}

void FileManager1Adaptor::ShowFolders(const QStringList &uriList, const QString &startUpId)
{
    m_app->showFolders(uriList, startUpId);
}

void FileManager1Adaptor::ShowItems(const QStringList &uriList, const QString &startUpId)
{
    m_app->showItems(uriList, startUpId);
}

void FileManager1Adaptor::ShowItemProperties(const QStringList &uriList, const QString &startUpId)
{
    m_app->showItemProperties(uriList, startUpId);
}
