// sedmio-capture — снимки экрана у KWin (org.kde.KWin.ScreenShot2) для
// «Ножниц» оболочки Sedmio (ScreenshotState.qml) и клавиш снимка
// (/usr/lib/sedmio/screenshot).
//
//   sedmio-capture screens <папка> <экран>...  каждый экран — <папка>/<экран>.png
//                                              (без сжатия: быстро), в вывод —
//                                              JSON {экран: {file, width, height}}
//   sedmio-capture crop <файл> <x> <y> <w> <h> <куда>   вырезать область (в точках снимка)
//   sedmio-capture workspace <куда>            все экраны одной картинкой
//   sedmio-capture active-window <куда>        активное окно
//   sedmio-capture window <куда>               окно, которое выберут щелчком (KWin)
//
// KWin отдаёт снимки только программам, у которых в .desktop-файле есть
// X-KDE-DBUS-Restricted-Interfaces=org.kde.KWin.ScreenShot2 и Exec — этот
// же исполняемый файл (usr/share/applications/sedmio-capture.desktop).
// Код выхода: 0 — готово, 1 — ошибка, 2 — отменили (Esc при выборе окна).

#include <QCoreApplication>
#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusUnixFileDescriptor>
#include <QDBusVariant>
#include <QDir>
#include <QFileInfo>
#include <QImage>
#include <QImageWriter>
#include <QJsonDocument>
#include <QJsonObject>
#include <QTextStream>

#include <cerrno>
#include <climits>
#include <cstring>
#include <fcntl.h>
#include <thread>
#include <unistd.h>

namespace
{
QTextStream err(stderr);

struct Result {
    QImage image;
    bool cancelled = false;
    QString error;
};

QVariantMap unwrap(const QVariant &value)
{
    // a{sv} приходит как QDBusArgument.
    QVariantMap map;
    if (value.canConvert<QDBusArgument>())
        value.value<QDBusArgument>() >> map;
    else
        map = value.toMap();
    return map;
}

// Вызов ScreenShot2.<method>(args..., options, fd): KWin пишет картинку в
// трубу, ответ — её размеры и формат.
Result capture(const QString &method, const QVariantList &arguments, const QVariantMap &options)
{
    Result result;
    int fds[2];
    if (pipe2(fds, O_CLOEXEC) != 0) {
        result.error = QStringLiteral("pipe: %1").arg(QString::fromLocal8Bit(strerror(errno)));
        return result;
    }

    // Читаем сразу, параллельно вызову: KWin пишет, пока мы ждём ответа,
    // и встал бы на полной трубе.
    QByteArray data;
    std::thread reader([fd = fds[0], &data] {
        char buffer[1 << 16];
        for (;;) {
            const ssize_t n = read(fd, buffer, sizeof buffer);
            if (n > 0)
                data.append(buffer, n);
            else if (n == 0 || errno != EINTR)
                break;
        }
        close(fd);
    });

    QDBusMessage reply;
    {
        QDBusMessage call = QDBusMessage::createMethodCall(QStringLiteral("org.kde.KWin"), QStringLiteral("/org/kde/KWin/ScreenShot2"),
                                                           QStringLiteral("org.kde.KWin.ScreenShot2"), method);
        QVariantList args = arguments;
        args << options << QVariant::fromValue(QDBusUnixFileDescriptor(fds[1]));
        close(fds[1]); // копия — в QDBusUnixFileDescriptor
        call.setArguments(args);
        // Выбор окна ждёт щелчка — без срока.
        reply = QDBusConnection::sessionBus().call(call, QDBus::Block, method == QLatin1String("CaptureInteractive") ? INT_MAX : 15000);
    } // здесь закрываются наши копии конца для записи: дальше — конец файла
    reader.join();

    if (reply.type() == QDBusMessage::ErrorMessage) {
        if (reply.errorName() == QLatin1String("org.kde.KWin.ScreenShot2.Error.Cancelled"))
            result.cancelled = true;
        else
            result.error = reply.errorName() + QStringLiteral(": ") + reply.errorMessage();
        return result;
    }
    const QVariantMap meta = unwrap(reply.arguments().value(0));
    const int width = meta.value(QStringLiteral("width")).toInt();
    const int height = meta.value(QStringLiteral("height")).toInt();
    const int stride = meta.value(QStringLiteral("stride")).toInt();
    const auto format = QImage::Format(meta.value(QStringLiteral("format")).toUInt());
    if (meta.value(QStringLiteral("type")).toString() != QLatin1String("raw") || width <= 0 || height <= 0
        || data.size() < qsizetype(stride) * height) {
        result.error = QStringLiteral("KWin вернул непонятный снимок");
        return result;
    }
    result.image = QImage(reinterpret_cast<const uchar *>(data.constData()), width, height, stride, format).copy();
    const qreal scale = meta.value(QStringLiteral("scale"), 1.0).toReal();
    if (scale > 0)
        result.image.setDevicePixelRatio(scale);
    return result;
}

// fast — без сжатия (временные файлы в /run), иначе — обычное сжатие.
bool save(const QImage &image, const QString &path, bool fast)
{
    QDir().mkpath(QFileInfo(path).absolutePath());
    const QString tmp = path + QStringLiteral(".part");
    QImageWriter writer(tmp, "png");
    writer.setQuality(fast ? 100 : 50);
    if (!writer.write(image)) {
        err << "sedmio-capture: " << path << ": " << writer.errorString() << Qt::endl;
        QFile::remove(tmp);
        return false;
    }
    QFile::remove(path);
    return QFile::rename(tmp, path);
}

int finish(const Result &result, const QString &out)
{
    if (result.cancelled)
        return 2;
    if (!result.error.isEmpty()) {
        err << "sedmio-capture: " << result.error << Qt::endl;
        return 1;
    }
    if (!save(result.image, out, false))
        return 1;
    QTextStream(stdout) << out << Qt::endl;
    return 0;
}

const QVariantMap screenOptions{{QStringLiteral("native-resolution"), true}, {QStringLiteral("include-cursor"), false}};
const QVariantMap windowOptions{{QStringLiteral("native-resolution"), true},
                                {QStringLiteral("include-cursor"), false},
                                {QStringLiteral("include-decoration"), true},
                                {QStringLiteral("include-shadow"), false}};
} // namespace

int main(int argc, char *argv[])
{
    QCoreApplication app(argc, argv);
    const QStringList args = app.arguments().mid(1);
    const QString command = args.value(0);

    if (command == QLatin1String("screens") && args.size() >= 3) {
        const QString dir = args.at(1);
        QJsonObject out;
        bool ok = true;
        for (const QString &name : args.mid(2)) {
            const Result result = capture(QStringLiteral("CaptureScreen"), {name}, screenOptions);
            if (!result.error.isEmpty() || result.image.isNull()) {
                err << "sedmio-capture: " << name << ": " << result.error << Qt::endl;
                ok = false;
                continue;
            }
            const QString file = dir + QLatin1Char('/') + QString(name).replace(QLatin1Char('/'), QLatin1Char('_')) + QStringLiteral(".png");
            if (!save(result.image, file, true)) {
                ok = false;
                continue;
            }
            out.insert(name, QJsonObject{{QStringLiteral("file"), file},
                                         {QStringLiteral("width"), result.image.width()},
                                         {QStringLiteral("height"), result.image.height()}});
        }
        QTextStream(stdout) << QJsonDocument(out).toJson(QJsonDocument::Compact) << Qt::endl;
        return ok || !out.isEmpty() ? 0 : 1;
    }

    if (command == QLatin1String("crop") && args.size() == 7) {
        QImage image(args.at(1));
        if (image.isNull()) {
            err << "sedmio-capture: не читается " << args.at(1) << Qt::endl;
            return 1;
        }
        const QRect area = QRect(args.at(2).toInt(), args.at(3).toInt(), args.at(4).toInt(), args.at(5).toInt()) & image.rect();
        if (area.isEmpty()) {
            err << "sedmio-capture: пустая область" << Qt::endl;
            return 1;
        }
        Result result;
        result.image = image.copy(area);
        return finish(result, args.at(6));
    }

    if (command == QLatin1String("workspace") && args.size() == 2)
        return finish(capture(QStringLiteral("CaptureWorkspace"), {}, screenOptions), args.at(1));
    if (command == QLatin1String("active-window") && args.size() == 2)
        return finish(capture(QStringLiteral("CaptureActiveWindow"), {}, windowOptions), args.at(1));
    if (command == QLatin1String("window") && args.size() == 2)
        return finish(capture(QStringLiteral("CaptureInteractive"), {0u}, windowOptions), args.at(1));

    err << "sedmio-capture screens <папка> <экран>... | crop <файл> <x> <y> <w> <h> <куда> | "
           "workspace <куда> | active-window <куда> | window <куда>"
        << Qt::endl;
    return 2;
}
