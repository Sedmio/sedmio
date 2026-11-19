// «Файлы» — файловый менеджер Sedmio вместо Dolphin. Интерфейс на QML
// в стиле оболочки, работа с файлами — KIO.
//
//   sedmio-files [папка или файл…]   файл — открыть его папку и выделить его
//   sedmio-files --daemon            без окна, ждать просьб по D-Bus
//                                    (так запускает шина для FileManager1)
//   sedmio-files --portal            окно выбора файлов для всех программ
//                                    (служба xdg-desktop-portal, см. portal.h)

#include "app.h"
#include "images.h"
#include "portal.h"
#include "prompts.h"

#include <QApplication>
#include <QCommandLineParser>
#include <QDir>
#include <QFileInfo>
#include <QIcon>
#include <QQmlApplicationEngine>
#include <QQuickStyle>
#include <QTimer>
#include <QUrl>

int main(int argc, char *argv[])
{
    // QApplication, а не QGuiApplication: редкие окна KIO (SSL, ошибки
    // открытия) пока на QtWidgets.
    QApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("sedmio-files"));
    app.setApplicationDisplayName(QStringLiteral("Файлы"));
    // Настройки — в ~/.config/sedmio/sedmio-files.conf
    app.setOrganizationName(QStringLiteral("sedmio"));
    app.setOrganizationDomain(QStringLiteral("sedmio.org"));
    // По нему KWin находит значок окна, а оболочка — программу в ходе копирования.
    app.setDesktopFileName(QStringLiteral("sedmio-files"));
    app.setWindowIcon(QIcon::fromTheme(QStringLiteral("system-file-manager")));

    QCommandLineParser parser;
    parser.addHelpOption();
    parser.addOption({QStringLiteral("daemon"), QStringLiteral("Не открывать окно, ждать просьб по D-Bus")});
    parser.addOption({QStringLiteral("portal"), QStringLiteral("Окно выбора файлов для других программ (xdg-desktop-portal)")});
    parser.addPositionalArgument(QStringLiteral("paths"), QStringLiteral("Какие папки открыть или какие файлы показать"));
    parser.process(app);

    // Окно выбора файлов — отдельный процесс, без имён «Файлов» на шине.
    if (parser.isSet(QStringLiteral("portal"))) {
        QGuiApplication::setQuitOnLastWindowClosed(false);
        // Задания KIO держат QEventLoopLocker: без окон конец задания
        // закрыл бы процесс посреди работы. Выходим сами — по простою.
        QCoreApplication::setQuitLockEnabled(false);
        // Заголовок окна — ровно тот, что дала программа, без « — Файлы».
        QGuiApplication::setApplicationDisplayName(QString());
        QQuickStyle::setStyle(QStringLiteral("Basic"));
        QQmlApplicationEngine engine;
        engine.addImageProvider(QStringLiteral("icon"), new IconProvider);
        engine.addImageProvider(QStringLiteral("thumb"), new ThumbnailProvider);
        FileChooserPortal portal(&engine);
        if (!portal.registerOnBus())
            return 0; // уже запущен другой
        return app.exec();
    }

    // Папки откроем, файлы покажем выделенными в их папках.
    QStringList folders;
    QStringList items;
    for (const QString &arg : parser.positionalArguments()) {
        const QUrl url = QUrl::fromUserInput(arg, QDir::currentPath(), QUrl::AssumeLocalFile);
        if (url.isLocalFile() && QFileInfo(url.toLocalFile()).isFile())
            items.append(url.toString());
        else
            folders.append(url.toString());
    }
    const bool daemon = parser.isSet(QStringLiteral("daemon"));
    if (!daemon && folders.isEmpty() && items.isEmpty())
        folders.append(QUrl::fromLocalFile(QDir::homePath()).toString());

    QQmlApplicationEngine engine;
    App files(&engine);

    // Уже запущены — пусть откроет окно тот процесс.
    if (!files.registerOnBus()) {
        bool ok = true;
        if (!folders.isEmpty())
            ok &= App::forward(QStringLiteral("ShowFolders"), folders);
        if (!items.isEmpty())
            ok &= App::forward(QStringLiteral("ShowItems"), items);
        if (ok)
            return 0;
        // Не ответил (завис?) — работаем сами.
    }

    QQuickStyle::setStyle(QStringLiteral("Basic"));
    Prompts::install();

    engine.addImageProvider(QStringLiteral("icon"), new IconProvider);
    engine.addImageProvider(QStringLiteral("thumb"), new ThumbnailProvider);
    // Окно вопросов (файл уже есть, чем открыть) — одно на всю программу.
    engine.loadFromModule("Sedmio.Files", "PromptWindow");
    if (engine.rootObjects().isEmpty())
        return 1;

    const QString token = qEnvironmentVariable("XDG_ACTIVATION_TOKEN");
    qunsetenv("XDG_ACTIVATION_TOKEN"); // не передавать запущенным программам
    if (!folders.isEmpty())
        files.showFolders(folders, token);
    if (!items.isEmpty())
        files.showItems(items, token);
    // Подняли по D-Bus, а просьбы так и не пришло — не висеть зря.
    if (daemon)
        QTimer::singleShot(30000, &files, &App::maybeQuit);

    return app.exec();
}
