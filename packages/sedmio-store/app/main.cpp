// «Программы» — магазин программ Sedmio: поиск по репозиториям Arch и
// Flathub в одном месте, установка, удаление и обновление программ.
// Обновление всей системы — в «Параметры» → «Обновление». См. catalog.h.

#include "jobs.h"
#include "storehost.h"

#include <QDBusConnection>
#include <QDBusMessage>

#include <QDir>
#include <QApplication>
#include <QIcon>
#include <QNetworkAccessManager>
#include <QNetworkDiskCache>
#include <QPixmap>
#include <QQmlApplicationEngine>
#include <QQmlNetworkAccessManagerFactory>
#include <QQuickImageProvider>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QStandardPaths>

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
        // «имя?palette=N» → «имя»: счётчик палитры только для перезапроса (SIcon).
        const qsizetype mark = id.lastIndexOf(QLatin1String("?palette="));
        QIcon icon = QIcon::fromTheme(mark < 0 ? id : id.left(mark));
        if (icon.isNull())
            icon = QIcon::fromTheme(QStringLiteral("application-x-executable"));
        const QPixmap pixmap = icon.pixmap(side, side);
        if (size)
            *size = pixmap.size();
        return pixmap;
    }
};

// Итог установки, когда окно закрыто или не в фокусе, — уведомлением.
void notify(const QString &title, const QString &body)
{
    QDBusMessage message = QDBusMessage::createMethodCall(QStringLiteral("org.freedesktop.Notifications"), QStringLiteral("/org/freedesktop/Notifications"),
                                                          QStringLiteral("org.freedesktop.Notifications"), QStringLiteral("Notify"));
    message << QStringLiteral("Программы") << uint(0) << QStringLiteral("system-software-install") << title << body << QStringList()
            << QVariantMap{{QStringLiteral("desktop-entry"), QStringLiteral("sedmio-store")}} << int(-1);
    QDBusConnection::sessionBus().send(message);
}

// Снимки экрана и значки из сети — с кэшем на диске: карточка, открытая
// второй раз, не качает их заново (и открывается без сети).
class CachedNetwork : public QQmlNetworkAccessManagerFactory
{
public:
    QNetworkAccessManager *create(QObject *parent) override
    {
        auto *manager = new QNetworkAccessManager(parent);
        auto *cache = new QNetworkDiskCache(manager);
        cache->setCacheDirectory(QStandardPaths::writableLocation(QStandardPaths::CacheLocation) + QStringLiteral("/network"));
        cache->setMaximumCacheSize(200 * 1024 * 1024);
        manager->setCache(cache);
        manager->setTransferTimeout(30000);
        return manager;
    }
};
} // namespace

int main(int argc, char *argv[])
{
    // QApplication, а не QGuiApplication: «Выбрать файл…» — окно выбора
    // файла Sedmio через портал (тема KDE даёт его только программам на
    // виджетах), иначе — запасное окно Qt без перевода.
    QApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("sedmio-store"));
    app.setApplicationDisplayName(QStringLiteral("Программы"));
    app.setOrganizationName(QStringLiteral("sedmio"));
    app.setOrganizationDomain(QStringLiteral("sedmio.org"));
    app.setDesktopFileName(QStringLiteral("sedmio-store"));
    app.setWindowIcon(QIcon::fromTheme(QStringLiteral("system-software-install")));
    QQuickStyle::setStyle(QStringLiteral("Basic"));

    // sedmio-store [id программы] — открыть её карточку.
    const QStringList args = app.arguments();
    const QString startApp = args.size() > 1 ? args.at(1) : QString();

    // Одно окно на сеанс: уже открыто — поднять его.
    StoreHost *host = StoreHost::instance();
    if (!host->registerOnBus()) {
        if (StoreHost::forward(startApp))
            return 0;
        // Запущенное не ответило (зависло?) — открываем своё окно.
    }
    host->setStartApp(startApp);

    CachedNetwork network; // живёт дольше движка
    QQmlApplicationEngine engine;
    engine.setNetworkAccessManagerFactory(&network);
    engine.addImageProvider(QStringLiteral("icon"), new IconProvider);
    engine.loadFromModule("Sedmio.Store", "StoreWindow");
    if (engine.rootObjects().isEmpty())
        return 1;
    auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().constFirst());
    host->setWindow(window);
    qunsetenv("XDG_ACTIVATION_TOKEN");

    // Окно закрыли, а установка идёт — работаем до конца очереди: pacman
    // всё равно доделает (он в своей службе), а Flatpak оборвался бы.
    Jobs *jobs = Jobs::instance();
    app.setQuitOnLastWindowClosed(false);
    auto quitIfIdle = [&app, window, jobs] {
        if ((!window || !window->isVisible()) && !jobs->busy())
            app.quit();
    };
    QObject::connect(&app, &QGuiApplication::lastWindowClosed, &app, quitIfIdle);
    QObject::connect(jobs, &Jobs::changed, &app, quitIfIdle, Qt::QueuedConnection);
    QObject::connect(jobs, &Jobs::finished, &app, [window](const QString &, const QString &name, const QString &action, bool ok, const QString &error) {
        if (window && window->isVisible() && window->isActive())
            return;
        if (name.isEmpty())
            return;
        const QString what = action == QLatin1String("remove") ? QStringLiteral("удалена") : action == QLatin1String("update") ? QStringLiteral("обновлена")
                                                                                                                              : QStringLiteral("установлена");
        if (ok)
            notify(QStringLiteral("«%1» %2").arg(name, what), QString());
        else if (error != QLatin1String("Отменено"))
            notify(QStringLiteral("«%1» — не получилось").arg(name), error);
    });
    return app.exec();
}
