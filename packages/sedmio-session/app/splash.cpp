// sedmio-splash: заставка при входе в сеанс Sedmio — вместо ksplashqml.
//
// Вид — /usr/share/sedmio/splash/Splash.qml (обои, знак, полоса загрузки)
// поверх всех мониторов. На шине — как ksplash (org.kde.KSplash
// /KSplash setStage), чтобы этапы слали те же: «startPlasma» и
// «ksmserver» — sedmio-session-manager, «desktop» — оболочка, когда обои
// на экране. Собрала шесть этапов (три первых ставит сама) — закрывается.
//
// Защита от поломок: вид не загрузился — заставки нет, программа сразу
// выходит; этап не пришёл (оболочка упала) — закрывается сама через 30 с.
// Мешать работе она не может: клавиатуру не берёт.

#include <LayerShellQt/Window>

#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QGuiApplication>
#include <QPointer>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QQuickItem>
#include <QQuickWindow>
#include <QScreen>
#include <QStringList>
#include <QTimer>

class Splash : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.kde.KSplash")

public:
    Splash()
    {
        // Ставит сама, как ksplash: начало, kcminit (его нет), KWin (уже есть).
        m_stages = {QStringLiteral("initial"), QStringLiteral("kcminit"), QStringLiteral("wm")};
        QTimer::singleShot(30000, this, &Splash::finish);
    }

    bool show()
    {
        const auto screens = QGuiApplication::screens();
        for (QScreen *screen : screens)
            showOn(screen);
        connect(qGuiApp, &QGuiApplication::screenAdded, this, &Splash::showOn);
        return !m_windows.isEmpty();
    }

public Q_SLOTS:
    Q_SCRIPTABLE void setStage(const QString &stage)
    {
        if (m_stages.contains(stage))
            return;
        m_stages.append(stage);
        update();
    }

private:
    void showOn(QScreen *screen)
    {
        QQmlComponent component(&m_engine, QUrl(QStringLiteral("file:///usr/share/sedmio/splash/Splash.qml")));
        // Сначала в окно, потом Component.onCompleted: анимация появления,
        // запущенная вне окна, так и осталась бы на нуле.
        QObject *object = component.beginCreate(m_engine.rootContext());
        auto *item = qobject_cast<QQuickItem *>(object);
        if (!item) {
            qWarning() << "sedmio-splash: вид не загрузился" << component.errors();
            if (object)
                component.completeCreate();
            delete object;
            return;
        }
        auto *window = new QQuickWindow;
        window->setColor(Qt::transparent);
        window->setFlag(Qt::FramelessWindowHint);
        item->setParentItem(window->contentItem());
        item->setSize(screen->size());
        item->setProperty("stage", int(m_stages.size()));
        component.completeCreate();
        connect(window, &QQuickWindow::widthChanged, item, [item, window] { item->setWidth(window->width()); });
        connect(window, &QQuickWindow::heightChanged, item, [item, window] { item->setHeight(window->height()); });
        window->setScreen(screen);
        window->setGeometry(screen->geometry());
        if (auto *layer = LayerShellQt::Window::get(window)) {
            layer->setLayer(LayerShellQt::Window::LayerOverlay);
            layer->setAnchors(LayerShellQt::Window::Anchors(LayerShellQt::Window::AnchorTop | LayerShellQt::Window::AnchorBottom
                                                            | LayerShellQt::Window::AnchorLeft | LayerShellQt::Window::AnchorRight));
            layer->setExclusiveZone(-1);
            layer->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityNone);
            layer->setScope(QStringLiteral("sedmio-splash"));
            layer->setScreen(screen);
        }
        connect(screen, &QObject::destroyed, window, &QObject::deleteLater);
        m_items.append(item);
        m_windows.append(window);
        update();
        window->show();
    }

    void update()
    {
        for (const auto &item : std::as_const(m_items)) {
            if (item)
                item->setProperty("stage", int(m_stages.size()));
        }
        if (m_stages.size() >= 6)
            finish();
    }

    void finish()
    {
        for (const auto &window : std::as_const(m_windows)) {
            if (window)
                window->hide();
        }
        qGuiApp->quit();
    }

    QQmlEngine m_engine;
    QStringList m_stages;
    QList<QPointer<QQuickItem>> m_items;
    QList<QPointer<QQuickWindow>> m_windows;
};

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("sedmio-splash"));
    app.setOrganizationName(QStringLiteral("sedmio"));

    Splash splash;
    QDBusConnection bus = QDBusConnection::sessionBus();
    bus.registerObject(QStringLiteral("/KSplash"), &splash, QDBusConnection::ExportScriptableSlots);
    // Заставка уже есть (вторая копия) — не нужна.
    if (!bus.registerService(QStringLiteral("org.kde.KSplash")))
        return 0;
    if (!splash.show())
        return 0;
    return app.exec();
}

#include "splash.moc"
