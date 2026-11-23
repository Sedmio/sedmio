// sedmio-screenshot-editor — редактор снимков «Ножниц»: перо, маркер,
// ластик, стрелки, рамки, текст, скрыть (пикселями), обрезка. Открывает
// уведомление о снимке («Изменить», /usr/lib/sedmio/screenshot).
//
//   sedmio-screenshot-editor <файл>
//
// Окно и рисование — qml/EditorWindow.qml, здесь — запуск, значки темы и
// сохранение (Editor).

#include "editor.h"

#include <QBuffer>
#include <QDir>
#include <QApplication>
#include <QFileInfo>
#include <QIcon>
#include <QImage>
#include <QImageWriter>
#include <QPixmap>
#include <QProcess>
#include <QQmlApplicationEngine>
#include <QQuickImageProvider>
#include <QQuickStyle>
#include <QSaveFile>
#include <QTextStream>
#include <QUrl>

namespace
{
QString startPath;

// image://icon/<имя> — значок из темы (как в sedmio-tasks).
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
        const qsizetype mark = id.lastIndexOf(QLatin1String("?palette="));
        QIcon icon = QIcon::fromTheme(mark < 0 ? id : id.left(mark));
        if (icon.isNull())
            icon = QIcon::fromTheme(QStringLiteral("unknown"));
        const QPixmap pixmap = icon.pixmap(side, side);
        if (size)
            *size = pixmap.size();
        return pixmap;
    }
};

QString localPath(const QString &target)
{
    const QUrl url(target);
    return url.isLocalFile() ? url.toLocalFile() : target;
}
} // namespace

Editor::Editor(QObject *parent)
    : QObject(parent)
    , m_path(startPath)
    , m_source(QUrl::fromLocalFile(startPath))
{
}

void Editor::setStartPath(const QString &path)
{
    startPath = path;
}

QString Editor::fileName() const
{
    return QFileInfo(m_path).fileName();
}

QString Editor::folder() const
{
    return QFileInfo(m_path).absolutePath();
}

bool Editor::save(const QVariant &image, const QString &target)
{
    const QImage picture = image.value<QImage>();
    const QString path = target.isEmpty() ? m_path : localPath(target);
    if (picture.isNull() || path.isEmpty())
        return false;

    // Через временный файл: прервалось — прежний снимок цел.
    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly))
        return false;
    QByteArray format = QFileInfo(path).suffix().toLower().toLatin1();
    if (format == "jpg")
        format = "jpeg";
    if (!QImageWriter::supportedImageFormats().contains(format))
        format = "png";
    QImageWriter writer(&file, format);
    if (format == "jpeg")
        writer.setQuality(92);
    // JPEG без прозрачности: фон белый, а не чёрный.
    const QImage out = format == "jpeg" ? picture.convertToFormat(QImage::Format_RGB32) : picture;
    if (!writer.write(out) || !file.commit())
        return false;

    if (path != m_path) {
        m_path = path;
        Q_EMIT pathChanged();
    }
    return true;
}

bool Editor::copy(const QVariant &image)
{
    const QImage picture = image.value<QImage>();
    if (picture.isNull())
        return false;
    QByteArray png;
    QBuffer buffer(&png);
    buffer.open(QIODevice::WriteOnly);
    if (!picture.save(&buffer, "PNG"))
        return false;

    // wl-copy читает картинку и уходит в фон — держать буфер.
    QProcess process;
    process.start(QStringLiteral("wl-copy"), {QStringLiteral("--type"), QStringLiteral("image/png")});
    if (!process.waitForStarted(2000))
        return false;
    process.write(png);
    process.closeWriteChannel();
    return process.waitForFinished(5000) && process.exitStatus() == QProcess::NormalExit && process.exitCode() == 0;
}

void Editor::openFolder() const
{
    QProcess::startDetached(QStringLiteral("xdg-open"), {folder()});
}

int main(int argc, char *argv[])
{
    // QApplication, а не QGuiApplication: «Сохранить как» — окно выбора
    // файла Sedmio через портал (тема KDE даёт его только программам на
    // виджетах), иначе — запасное окно Qt без перевода.
    QApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("sedmio-screenshot-editor"));
    app.setApplicationDisplayName(QStringLiteral("Ножницы"));
    app.setOrganizationName(QStringLiteral("sedmio"));
    app.setOrganizationDomain(QStringLiteral("sedmio.org"));
    app.setDesktopFileName(QStringLiteral("sedmio-screenshot-editor"));
    app.setWindowIcon(QIcon::fromTheme(QStringLiteral("accessories-screenshot-tool")));
    QQuickStyle::setStyle(QStringLiteral("Basic"));

    const QStringList args = app.arguments();
    if (args.size() < 2) {
        QTextStream(stderr) << "Использование: sedmio-screenshot-editor <файл>\n";
        return 2;
    }
    const QFileInfo file(localPath(args.at(1)));
    if (!file.isFile() || QImage(file.absoluteFilePath()).isNull()) {
        QTextStream(stderr) << "sedmio-screenshot-editor: не картинка: " << args.at(1) << '\n';
        return 1;
    }
    Editor::setStartPath(file.absoluteFilePath());

    QQmlApplicationEngine engine;
    engine.addImageProvider(QStringLiteral("icon"), new IconProvider);
    engine.loadFromModule("Sedmio.ScreenshotEditor", "EditorWindow");
    if (engine.rootObjects().isEmpty())
        return 1;
    qunsetenv("XDG_ACTIVATION_TOKEN");
    return app.exec();
}
