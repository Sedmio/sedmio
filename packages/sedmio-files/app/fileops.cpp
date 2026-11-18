#include "fileops.h"
#include "app.h"
#include "images.h"

#include <KApplicationTrader>
#include <KFileUtils>
#include <KIO/ApplicationLauncherJob>
#include <KIO/CopyJob>
#include <KIO/DeleteJob>
#include <KIO/EmptyTrashJob>
#include <KIO/FileUndoManager>
#include <KIO/MkdirJob>
#include <KIO/JobUiDelegateFactory>
#include <KIO/OpenUrlJob>
#include <KIO/Paste>
#include <KIO/PasteJob>
#include <KIO/RestoreJob>
#include <KIO/SimpleJob>
#include <KService>
#include <KUrlMimeData>

#include <QClipboard>
#include <QDir>
#include <QFileInfo>
#include <QGuiApplication>
#include <QImageReader>
#include <QLocale>
#include <QMimeData>
#include <QMimeDatabase>
#include <QStringDecoder>
#include <QRegularExpression>
#include <QStorageInfo>

namespace
{
QClipboard *clipboard()
{
    return QGuiApplication::clipboard();
}

constexpr int ERR_USER_CANCELED = KJob::KilledJobError;
} // namespace

FileOps::FileOps(QObject *parent)
    : QObject(parent)
{
    connect(clipboard(), &QClipboard::dataChanged, this, &FileOps::clipboardChanged);

    auto *undo = KIO::FileUndoManager::self();
    connect(undo, &KIO::FileUndoManager::undoAvailable, this, &FileOps::undoChanged);
    connect(undo, &KIO::FileUndoManager::undoTextChanged, this, &FileOps::undoChanged);
}

void FileOps::track(KJob *job)
{
    // Пока задание идёт, программа не закроется вместе с последним окном.
    if (App *app = App::instance()) {
        app->jobStarted();
        connect(job, &QObject::destroyed, app, &App::jobFinished);
    }
}

void FileOps::watch(KJob *job)
{
    track(job);
    connect(job, &KJob::result, this, [this, job] {
        if (job->error() && job->error() != ERR_USER_CANCELED)
            Q_EMIT error(job->errorString());
    });
}

bool FileOps::canPaste() const
{
    const QMimeData *data = clipboard()->mimeData();
    return data && data->hasUrls();
}

QList<QUrl> FileOps::cutUrls() const
{
    const QMimeData *data = clipboard()->mimeData();
    if (!data || !KIO::isClipboardDataCut(data))
        return {};
    return KUrlMimeData::urlsFromMimeData(data);
}

bool FileOps::canUndo() const
{
    return KIO::FileUndoManager::self()->isUndoAvailable();
}

QString FileOps::undoText() const
{
    // «Отм&енить: копирование» → «Отменить: копирование»
    return KIO::FileUndoManager::self()->undoText().remove(QLatin1Char('&'));
}

void FileOps::copyText(const QString &text)
{
    clipboard()->setText(text);
}

void FileOps::copyPaths(const QList<QUrl> &urls)
{
    QStringList paths;
    for (const QUrl &url : urls)
        paths.append(url.isLocalFile() ? url.toLocalFile() : url.toDisplayString());
    clipboard()->setText(paths.join(QLatin1Char('\n')));
}

void FileOps::open(const QUrl &url)
{
    auto *job = new KIO::OpenUrlJob(url);
    job->setUiDelegate(KIO::createDefaultJobUiDelegate(KJobUiDelegate::AutoHandlingEnabled, nullptr));
    // Запускаемые файлы и скрипты — спросить, а не запускать молча.
    job->setShowOpenOrExecuteDialog(true);
    job->start();
}

QVariantList FileOps::applications(const QString &mimeType) const
{
    QVariantList list;
    const KService::List services = KApplicationTrader::queryByMimeType(mimeType);
    for (const KService::Ptr &service : services) {
        list.append(QVariantMap{
            {QStringLiteral("id"), service->storageId()},
            {QStringLiteral("name"), service->name()},
            {QStringLiteral("icon"), service->icon()},
        });
    }
    return list;
}

void FileOps::openWith(const QList<QUrl> &urls, const QString &serviceId)
{
    KIO::ApplicationLauncherJob *job;
    if (serviceId.isEmpty()) {
        job = new KIO::ApplicationLauncherJob(); // спросит, чем открыть
    } else {
        const KService::Ptr service = KService::serviceByStorageId(serviceId);
        if (!service)
            return;
        job = new KIO::ApplicationLauncherJob(service);
    }
    job->setUrls(urls);
    job->setUiDelegate(KIO::createDefaultJobUiDelegate(KJobUiDelegate::AutoHandlingEnabled, nullptr));
    job->start();
}

void FileOps::putOnClipboard(const QList<QUrl> &urls, bool cut)
{
    if (urls.isEmpty())
        return;

    auto *data = new QMimeData;
    KUrlMimeData::setUrls(urls, urls, data);
    KIO::setClipboardDataCut(data, cut);

    // Чтобы вставить пути в текстовое поле или терминал.
    QStringList paths;
    for (const QUrl &url : urls)
        paths.append(url.isLocalFile() ? url.toLocalFile() : url.toString());
    data->setText(paths.join(QLatin1Char('\n')));

    // Для программ на GTK.
    QByteArray gnome = cut ? "cut" : "copy";
    for (const QUrl &url : urls)
        gnome += '\n' + url.toEncoded();
    data->setData(QStringLiteral("x-special/gnome-copied-files"), gnome);

    clipboard()->setMimeData(data);
}

void FileOps::copy(const QList<QUrl> &urls)
{
    putOnClipboard(urls, false);
}

void FileOps::cut(const QList<QUrl> &urls)
{
    putOnClipboard(urls, true);
}

void FileOps::paste(const QUrl &destination)
{
    const QMimeData *data = clipboard()->mimeData();
    if (!data || !data->hasUrls())
        return;

    const bool wasCut = KIO::isClipboardDataCut(data);
    KIO::PasteJob *job = KIO::paste(data, destination);
    watch(job);
    if (wasCut) {
        // Перенесённое второй раз не вставить: буфер больше не нужен.
        connect(job, &KJob::result, this, [job] {
            if (!job->error())
                clipboard()->clear();
        });
    }
}

bool FileOps::sameDevice(const QList<QUrl> &urls, const QUrl &destination) const
{
    if (urls.isEmpty() || !destination.isLocalFile())
        return false;
    const QString target = QStorageInfo(destination.toLocalFile()).rootPath();
    for (const QUrl &url : urls) {
        if (!url.isLocalFile() || QStorageInfo(url.toLocalFile()).rootPath() != target)
            return false;
    }
    return true;
}

void FileOps::drop(const QList<QUrl> &urls, const QUrl &destination, bool move)
{
    if (urls.isEmpty())
        return;
    // В ту же папку, откуда взяли, переносить нечего.
    const QUrl parent = urls.first().adjusted(QUrl::RemoveFilename | QUrl::StripTrailingSlash);
    if (move && parent == destination.adjusted(QUrl::StripTrailingSlash))
        return;
    for (const QUrl &url : urls) {
        if (url == destination || url.isParentOf(destination))
            return; // папку в саму себя
    }

    KIO::CopyJob *job = move ? KIO::move(urls, destination) : KIO::copy(urls, destination);
    KIO::FileUndoManager::self()->recordCopyJob(job);
    watch(job);
}

void FileOps::trash(const QList<QUrl> &urls)
{
    if (urls.isEmpty())
        return;
    KIO::Job *job = KIO::trash(urls);
    KIO::FileUndoManager::self()->recordJob(KIO::FileUndoManager::Trash, urls, QUrl(QStringLiteral("trash:/")), job);
    track(job);
    // Корзины нет (tmpfs, флешка без прав) или файл ей не по размеру —
    // спросим, удалить ли насовсем, вместо голой ошибки.
    connect(job, &KJob::result, this, [this, job, urls] {
        switch (job->error()) {
        case 0:
        case ERR_USER_CANCELED:
            return;
        case KIO::ERR_TRASH_NOT_AVAILABLE:
            Q_EMIT trashUnavailable(urls, QStringLiteral("Здесь нет корзины."));
            return;
        case KIO::ERR_TRASH_FILE_TOO_LARGE:
            Q_EMIT trashUnavailable(urls, QStringLiteral("Это не помещается в корзину."));
            return;
        default:
            Q_EMIT error(job->errorString());
        }
    });
}

void FileOps::remove(const QList<QUrl> &urls)
{
    if (urls.isEmpty())
        return;
    watch(KIO::del(urls));
}

void FileOps::restore(const QList<QUrl> &urls)
{
    if (urls.isEmpty())
        return;
    watch(KIO::restoreFromTrash(urls));
}

void FileOps::emptyTrash()
{
    watch(KIO::emptyTrash());
}

QString FileOps::rename(const QUrl &url, const QString &newName)
{
    if (url.isEmpty() || url.fileName().isEmpty())
        return {};
    const QString name = newName.trimmed();
    if (name.isEmpty())
        return QStringLiteral("Имя не может быть пустым");
    if (name.contains(QLatin1Char('/')))
        return QStringLiteral("В имени не может быть «/»");
    if (name == QLatin1String(".") || name == QLatin1String(".."))
        return QStringLiteral("Такое имя нельзя");
    if (name == url.fileName())
        return {};

    QUrl target = url.adjusted(QUrl::RemoveFilename);
    target.setPath(target.path() + name);
    if (target.isLocalFile() && QFileInfo::exists(target.toLocalFile()))
        return QStringLiteral("Здесь уже есть «%1»").arg(name);

    KIO::Job *job = KIO::moveAs(url, target, KIO::HideProgressInfo);
    KIO::FileUndoManager::self()->recordJob(KIO::FileUndoManager::Rename, {url}, target, job);
    watch(job);
    return {};
}

QString FileOps::createFolder(const QUrl &directory, const QString &name)
{
    QString finalName = name;
    QUrl url = directory.adjusted(QUrl::StripTrailingSlash);
    url.setPath(url.path() + QLatin1Char('/') + finalName);
    if (url.isLocalFile() && QFileInfo::exists(url.toLocalFile())) {
        finalName = KFileUtils::suggestName(directory, name);
        url = directory.adjusted(QUrl::StripTrailingSlash);
        url.setPath(url.path() + QLatin1Char('/') + finalName);
    }

    KIO::SimpleJob *job = KIO::mkdir(url);
    KIO::FileUndoManager::self()->recordJob(KIO::FileUndoManager::Mkdir, {url}, url, job);
    watch(job);
    return finalName;
}

void FileOps::undo()
{
    KIO::FileUndoManager::self()->undo();
}

QString FileOps::previewKind(const QString &mimeType) const
{
    static const QList<QByteArray> images = QImageReader::supportedMimeTypes();
    if (images.contains(mimeType.toLatin1()))
        return QStringLiteral("image");
    const QMimeType mime = QMimeDatabase().mimeTypeForName(mimeType);
    if (mime.inherits(QStringLiteral("text/plain")))
        return QStringLiteral("text");
    if (canPreview(mimeType))
        return QStringLiteral("thumb");
    return QStringLiteral("other");
}

QVariantMap FileOps::readText(const QUrl &url) const
{
    // Больше и не прочесть глазами, и не стоит держать в памяти.
    constexpr qint64 limit = 256 * 1024;
    QFile file(url.toLocalFile());
    if (!url.isLocalFile() || !file.open(QIODevice::ReadOnly))
        return {};
    const QByteArray data = file.read(limit);
    QString text = QStringDecoder(QStringDecoder::Utf8)(data);
    // Обрезали посреди строки — показываем до последней целой.
    const bool truncated = file.size() > limit;
    if (truncated) {
        const int end = text.lastIndexOf(QLatin1Char('\n'));
        if (end > 0)
            text.truncate(end);
    }
    return {{QStringLiteral("text"), text}, {QStringLiteral("truncated"), truncated}};
}

QString FileOps::prettyPath(const QUrl &url) const
{
    if (!url.isLocalFile())
        return url.toDisplayString(QUrl::RemoveUserInfo | QUrl::StripTrailingSlash);
    const QString path = url.toLocalFile();
    const QString home = QDir::homePath();
    if (path == home)
        return QStringLiteral("~");
    if (path.startsWith(home + QLatin1Char('/')))
        return QLatin1Char('~') + path.mid(home.size());
    return path;
}

QString FileOps::formatSize(qreal bytes) const
{
    static const char *units[] = {"Б", "КБ", "МБ", "ГБ", "ТБ"};
    int unit = 0;
    while (bytes >= 1024 && unit < 4) {
        bytes /= 1024;
        ++unit;
    }
    const QLocale locale(QLocale::Russian);
    const QString number = unit == 0 || bytes >= 100 ? locale.toString(qRound(bytes))
                                                     : locale.toString(bytes, 'f', 1).remove(QRegularExpression(QStringLiteral(",0$")));
    return number + QLatin1Char(' ') + QString::fromUtf8(units[unit]);
}

QUrl FileOps::homeUrl() const
{
    return QUrl::fromLocalFile(QDir::homePath());
}

QVariantList FileOps::crumbs(const QUrl &url) const
{
    QVariantList list;
    auto add = [&list](const QString &name, const QUrl &url) {
        list.append(QVariantMap{{QStringLiteral("name"), name}, {QStringLiteral("url"), url}});
    };

    if (url.scheme() == QLatin1String("trash")) {
        add(QStringLiteral("Корзина"), QUrl(QStringLiteral("trash:/")));
        QUrl part(QStringLiteral("trash:/"));
        const QStringList segments = url.path().split(QLatin1Char('/'), Qt::SkipEmptyParts);
        for (const QString &segment : segments) {
            part.setPath(part.path() + (part.path().endsWith(QLatin1Char('/')) ? QString() : QStringLiteral("/")) + segment);
            add(segment, part);
        }
        return list;
    }

    QString path = url.path();
    QUrl base = url;
    base.setPath(QStringLiteral("/"));
    QString basePath = QStringLiteral("/");

    if (url.isLocalFile()) {
        const QString home = QDir::homePath();
        if (path == home || path.startsWith(home + QLatin1Char('/'))) {
            add(QStringLiteral("Домашняя папка"), QUrl::fromLocalFile(home));
            basePath = home;
        } else {
            add(QStringLiteral("Компьютер"), QUrl::fromLocalFile(QStringLiteral("/")));
        }
    } else {
        add(url.host().isEmpty() ? url.scheme() : url.host(), base);
    }

    const QStringList segments = path.mid(basePath.size()).split(QLatin1Char('/'), Qt::SkipEmptyParts);
    QString current = basePath;
    for (const QString &segment : segments) {
        if (!current.endsWith(QLatin1Char('/')))
            current += QLatin1Char('/');
        current += segment;
        QUrl part = url;
        part.setPath(current);
        add(segment, part);
    }
    return list;
}

QUrl FileOps::urlFromInput(const QString &text) const
{
    QString input = text.trimmed();
    if (input == QLatin1String("~"))
        input = QDir::homePath();
    else if (input.startsWith(QLatin1String("~/")))
        input = QDir::homePath() + input.mid(1);
    return QUrl::fromUserInput(input, QDir::homePath(), QUrl::AssumeLocalFile);
}
