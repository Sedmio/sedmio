// «Диспетчер задач» (Ctrl+Shift+Esc): что работает и сколько берёт,
// «Завершить» для зависшего, перезапуск оболочки. Отдельная маленькая
// программа (а не раздел «Параметров»): его открывают, когда что-то
// сломалось, — он не должен ломаться вместе с остальным. Зависит только
// от Qt и KService. См. tasks.h.

#include "tasks.h"

#include <QGuiApplication>
#include <QIcon>
#include <QPixmap>
#include <QQmlApplicationEngine>
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
    QGuiApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("sedmio-tasks"));
    app.setApplicationDisplayName(QStringLiteral("Диспетчер задач"));
    app.setOrganizationName(QStringLiteral("sedmio"));
    app.setOrganizationDomain(QStringLiteral("sedmio.org"));
    app.setDesktopFileName(QStringLiteral("sedmio-tasks"));
    app.setWindowIcon(QIcon::fromTheme(QStringLiteral("utilities-system-monitor")));
    QQuickStyle::setStyle(QStringLiteral("Basic"));

    // Одно окно на сеанс: уже открыт — поднять его.
    TasksHost host;
    if (!host.registerOnBus()) {
        if (TasksHost::forward())
            return 0;
        // Запущенный не ответил (завис?) — открываем своё окно.
    }

    QQmlApplicationEngine engine;
    engine.addImageProvider(QStringLiteral("icon"), new IconProvider);
    engine.loadFromModule("Sedmio.Tasks", "TasksWindow");
    if (engine.rootObjects().isEmpty())
        return 1;
    host.setWindow(qobject_cast<QQuickWindow *>(engine.rootObjects().constFirst()));
    qunsetenv("XDG_ACTIVATION_TOKEN");
    return app.exec();
}
