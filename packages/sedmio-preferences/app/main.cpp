// «Параметры» — настройки Sedmio вместо параметров системы KDE. Интерфейс на
// QML в стиле оболочки, работа — движки KDE и systemd (libkscreen,
// timedated, hostnamed). Чего у нас пока нет, открывается в параметрах KDE.
//
//   sedmio-preferences [раздел]   display | wallpaper | mouse | keyboard | power | defaults | datetime | about
//   sedmio-preferences --display-switcher   выбор режима экранов (Meta+P) вместо
//                                           kscreen_osd_service, см. displayswitcher.h

#include "app.h"
#include "displayswitcher.h"

#include <QApplication>
#include <QIcon>
#include <QPixmap>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickImageProvider>
#include <QQuickStyle>
#include <QQuickWindow>

namespace
{
// image://icon/<имя> — значок из темы.
class IconProvider : public QQuickImageProvider
{
public:
    IconProvider()
        : QQuickImageProvider(QQuickImageProvider::Pixmap)
    {
    }

    QPixmap requestPixmap(const QString &id, QSize *size, const QSize &requested) override
    {
        const int side = qMax(requested.width(), requested.height()) > 0 ? qMax(requested.width(), requested.height()) : 64;
        QIcon icon = QIcon::fromTheme(id);
        if (icon.isNull())
            icon = QIcon::fromTheme(QStringLiteral("unknown"));
        const QPixmap pixmap = icon.pixmap(side, side);
        if (size)
            *size = pixmap.size();
        return pixmap;
    }
};
} // namespace

int main(int argc, char *argv[])
{
    // QApplication, а не QGuiApplication: «Выбрать файл…» в обоях — окно
    // выбора файла KDE, а оно на виджетах.
    QApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("sedmio-preferences"));
    app.setApplicationDisplayName(QStringLiteral("Параметры"));
    app.setOrganizationName(QStringLiteral("sedmio"));
    app.setOrganizationDomain(QStringLiteral("sedmio.org"));
    app.setDesktopFileName(QStringLiteral("sedmio-preferences"));
    app.setWindowIcon(QIcon::fromTheme(QStringLiteral("preferences-system")));

    const QStringList args = app.arguments().mid(1);
    QQuickStyle::setStyle(QStringLiteral("Basic"));

    if (args.contains(QStringLiteral("--display-switcher"))) {
        DisplaySwitcher switcher;
        QQmlApplicationEngine engine;
        engine.rootContext()->setContextProperty(QStringLiteral("Switcher"), &switcher);
        engine.loadFromModule("Sedmio.Preferences", "DisplaySwitcher");
        // Окно не загрузилось — выходим, не заняв имя на шине: служба
        // запустит вместо нас kscreen_osd_service (plasma-kscreen-osd.service.d).
        if (engine.rootObjects().isEmpty())
            return 1;
        switcher.setWindow(qobject_cast<QQuickWindow *>(engine.rootObjects().constFirst()));
        if (!switcher.registerOnBus())
            return 1;
        app.setQuitOnLastWindowClosed(false);
        return app.exec();
    }

    const QString page = args.isEmpty() ? QString() : args.constFirst();

    App preferences;
    if (!preferences.registerOnBus()) {
        if (App::forward(page))
            return 0;
        // Запущенный не ответил (завис?) — работаем сами.
    }
    if (!page.isEmpty())
        preferences.setPage(page);

    QQmlApplicationEngine engine;
    engine.addImageProvider(QStringLiteral("icon"), new IconProvider);
    engine.rootContext()->setContextProperty(QStringLiteral("App"), &preferences);
    engine.loadFromModule("Sedmio.Preferences", "Main");
    if (engine.rootObjects().isEmpty())
        return 1;
    preferences.setWindow(qobject_cast<QQuickWindow *>(engine.rootObjects().constFirst()));

    qunsetenv("XDG_ACTIVATION_TOKEN");
    return app.exec();
}
