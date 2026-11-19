#include "wallpapers.h"

#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QImageReader>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSaveFile>
#include <QScreen>
#include <QStandardPaths>
#include <QUrl>

#include <cstdio>

namespace
{
QString configPath()
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation) + QStringLiteral("/sedmio/wallpaper.json");
}

const QStringList imageFilters = {QStringLiteral("*.jpg"), QStringLiteral("*.jpeg"), QStringLiteral("*.png"),
                                  QStringLiteral("*.webp"), QStringLiteral("*.avif"), QStringLiteral("*.jxl")};

// Набор обоев KDE (папка с contents/images/<ширина>x<высота>.<ext>): там
// бывают и панорама на два монитора, и вертикальная для телефона. Берём
// ближайшую по пропорциям к экрану, из таких — самую большую.
QString bestIn(const QString &dir)
{
    const QScreen *screen = QGuiApplication::primaryScreen();
    const QSize target = screen ? screen->size() : QSize(16, 9);
    const double targetAspect = double(target.width()) / qMax(1, target.height());

    QString best;
    double bestDiff = 1e9;
    qint64 bestArea = 0;
    const auto files = QDir(dir).entryInfoList(imageFilters, QDir::Files);
    for (const QFileInfo &file : files) {
        const QSize size = QImageReader(file.filePath()).size();
        if (size.isEmpty())
            continue;
        // До сотых: 16:9 и 16:10 разные, 1920×1080 и 3840×2160 — одно.
        const double diff = qRound(qAbs(double(size.width()) / size.height() - targetAspect) * 100) / 100.0;
        const qint64 area = qint64(size.width()) * size.height();
        if (diff < bestDiff || (diff == bestDiff && area > bestArea)) {
            bestDiff = diff;
            bestArea = area;
            best = file.filePath();
        }
    }
    return best;
}

// Ссылка на выбранную картинку для экрана блокировки и заставки входа: они
// работают от имени пользователя, но прочитать wallpaper.json из своего QML
// не могут, а картинку по постоянному адресу — могут. Пусто — ссылки нет.
QString linkPath()
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericStateLocation) + QStringLiteral("/sedmio/wallpaper");
}

void syncLink(const QString &image)
{
    const QString link = linkPath();
    if (image.isEmpty()) {
        QFile::remove(link);
        return;
    }
    if (QFileInfo(link).symLinkTarget() == image)
        return;
    QDir().mkpath(QFileInfo(link).path());
    // Подменяем разом: экран блокировки не увидит «ссылки нет».
    const QString temporary = link + QStringLiteral(".new");
    QFile::remove(temporary);
    if (QFile::link(image, temporary))
        ::rename(QFile::encodeName(temporary).constData(), QFile::encodeName(link).constData());
}

QString prettyName(const QString &base)
{
    QString name = base;
    name.replace(QLatin1Char('_'), QLatin1Char(' ')).replace(QLatin1Char('-'), QLatin1Char(' '));
    if (!name.isEmpty())
        name[0] = name[0].toUpper();
    return name;
}
} // namespace

Wallpapers::Wallpapers(QObject *parent)
    : QObject(parent)
{
    readCurrent();
    rescan();
    // Сменили обои не мы (другое окно «Параметров», вручную) — показать.
    const QString path = configPath();
    QDir().mkpath(QFileInfo(path).path());
    m_watcher.addPath(QFileInfo(path).path());
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, this, &Wallpapers::readCurrent);
}

void Wallpapers::readCurrent()
{
    QFile file(configPath());
    QString image;
    if (file.open(QIODevice::ReadOnly))
        image = QJsonDocument::fromJson(file.readAll()).object().value(QStringLiteral("image")).toString();
    syncLink(image);
    if (image != m_current) {
        m_current = image;
        Q_EMIT currentChanged();
    }
}

void Wallpapers::rescan()
{
    QVariantList images;
    QStringList seen;
    auto add = [&](const QString &path, const QString &name) {
        if (path.isEmpty() || seen.contains(path))
            return;
        seen.append(path);
        // url — для Image: «#» и пробелы в имени файла в строку не склеишь.
        images.append(QVariantMap{{QStringLiteral("path"), path},
                                  {QStringLiteral("url"), QUrl::fromLocalFile(path)},
                                  {QStringLiteral("name"), name}});
    };

    // Системные: наши, KDE, общие.
    QStringList roots;
    for (const QString &data : QStandardPaths::standardLocations(QStandardPaths::GenericDataLocation)) {
        roots << data + QStringLiteral("/sedmio/wallpapers") << data + QStringLiteral("/wallpapers")
              << data + QStringLiteral("/backgrounds");
    }
    for (const QString &root : std::as_const(roots)) {
        const QDir dir(root);
        if (!dir.exists())
            continue;
        for (const QFileInfo &entry : dir.entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name)) {
            const QString images = entry.filePath() + QStringLiteral("/contents/images");
            if (!QDir(images).exists())
                continue;
            // Выбрана картинка из этого набора — плитка набора она и есть.
            const bool chosenHere = m_current.startsWith(images + QLatin1Char('/')) && QFileInfo::exists(m_current);
            add(chosenHere ? m_current : bestIn(images), prettyName(entry.fileName()));
        }
        QDirIterator it(root, imageFilters, QDir::Files, QDirIterator::Subdirectories);
        while (it.hasNext()) {
            const QString path = it.next();
            if (path.contains(QLatin1String("/contents/")))
                continue; // наборы KDE уже взяли целиком
            add(path, prettyName(QFileInfo(path).completeBaseName()));
        }
    }

    // Свои картинки — из «Изображений» (без вложенных папок: там бывают тысячи).
    const QString pictures = QStandardPaths::writableLocation(QStandardPaths::PicturesLocation);
    for (const QFileInfo &file : QDir(pictures).entryInfoList(imageFilters, QDir::Files, QDir::Time))
        add(file.filePath(), file.completeBaseName());

    // Выбранные когда-то из другого места — тоже в списке.
    if (!m_current.isEmpty() && QFileInfo::exists(m_current))
        add(m_current, QFileInfo(m_current).completeBaseName());

    m_images = images;
    Q_EMIT imagesChanged();
}

void Wallpapers::choose(const QString &pathOrUrl)
{
    QString path = pathOrUrl;
    if (path.startsWith(QLatin1String("file:")))
        path = QUrl(path).toLocalFile();
    if (!path.isEmpty() && QImageReader(path).size().isEmpty()) {
        m_error = QStringLiteral("Эту картинку не получается открыть.");
        Q_EMIT currentChanged();
        return;
    }

    // Целиком или никак: оболочка не должна прочитать половину файла.
    QSaveFile file(configPath());
    QDir().mkpath(QFileInfo(configPath()).path());
    if (!file.open(QIODevice::WriteOnly)) {
        m_error = QStringLiteral("Не удалось сохранить выбор: %1").arg(file.errorString());
        Q_EMIT currentChanged();
        return;
    }
    file.write(QJsonDocument(QJsonObject{{QStringLiteral("image"), path}}).toJson());
    if (!file.commit()) {
        m_error = QStringLiteral("Не удалось сохранить выбор: %1").arg(file.errorString());
        Q_EMIT currentChanged();
        return;
    }
    syncLink(path);
    m_error.clear();
    m_current = path;
    Q_EMIT currentChanged();
    if (!path.isEmpty() && !std::any_of(m_images.cbegin(), m_images.cend(), [&](const QVariant &v) {
            return v.toMap().value(QStringLiteral("path")).toString() == path;
        }))
        rescan();
}
