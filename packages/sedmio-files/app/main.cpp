// «Файлы» — файловый менеджер Sedmio вместо Dolphin. Интерфейс на QML
// в стиле оболочки, работа с файлами — KIO.
//
//   sedmio-files [папка]

#include "images.h"

#include <QApplication>
#include <QCommandLineParser>
#include <QDir>
#include <QIcon>
#include <QQmlApplicationEngine>
#include <QQuickStyle>
#include <QUrl>

int main(int argc, char *argv[])
{
    // QApplication, а не QGuiApplication: окна KIO (файл уже есть, открыть
    // с помощью) пока на QtWidgets.
    QApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("sedmio-files"));
    app.setApplicationDisplayName(QStringLiteral("Файлы"));
    // Настройки — в ~/.config/sedmio/sedmio-files.conf
    app.setOrganizationName(QStringLiteral("sedmio"));
    app.setOrganizationDomain(QStringLiteral("sedmio.org"));
    // По нему KWin находит значок окна, а оболочка — программу в ходе копирования.
    app.setDesktopFileName(QStringLiteral("sedmio-files"));
    app.setWindowIcon(QIcon::fromTheme(QStringLiteral("system-file-manager")));

    // Свои элементы, без стиля Plasma.
    QQuickStyle::setStyle(QStringLiteral("Basic"));

    QCommandLineParser parser;
    parser.addHelpOption();
    parser.addPositionalArgument(QStringLiteral("folder"), QStringLiteral("Какую папку открыть"));
    parser.process(app);

    QUrl start = QUrl::fromLocalFile(QDir::homePath());
    if (!parser.positionalArguments().isEmpty())
        start = QUrl::fromUserInput(parser.positionalArguments().constFirst(), QDir::currentPath(), QUrl::AssumeLocalFile);

    QQmlApplicationEngine engine;
    engine.addImageProvider(QStringLiteral("icon"), new IconProvider);
    engine.addImageProvider(QStringLiteral("thumb"), new ThumbnailProvider);
    engine.setInitialProperties({{QStringLiteral("startUrl"), start}});
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed, &app, [] {
        QCoreApplication::exit(1);
    }, Qt::QueuedConnection);
    engine.loadFromModule("Sedmio.Files", "Main");

    return app.exec();
}
