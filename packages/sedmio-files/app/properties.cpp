#include "properties.h"
#include "images.h"

#include <KApplicationTrader>
#include <KIO/ChmodJob>
#include <KIO/DirectorySizeJob>
#include <KIO/FileSystemFreeSpaceJob>
#include <KIO/StatJob>
#include <KService>
#include <KUser>

#include <unistd.h>

namespace
{
// Чтение, запись, запуск для владельца; у группы и остальных — сдвиг.
constexpr int R = 4, W = 2, X = 1;
int shift(int who)
{
    return (2 - who) * 3;
}

// Что спрашивать у KIO: всё обычное плюс тип по содержимому.
constexpr KIO::StatDetails details = KIO::StatDefaultDetails | KIO::StatMimeType;
} // namespace

Properties::Properties(QObject *parent)
    : QObject(parent)
{
    // Подсчёт размера папок не сообщает, как идёт, — смотрим сами.
    m_sizeTimer.setInterval(200);
    connect(&m_sizeTimer, &QTimer::timeout, this, [this] {
        if (!m_sizeJob)
            return;
        m_size = m_sizeJob->totalSize();
        m_files = m_sizeJob->totalFiles();
        m_folders = m_sizeJob->totalSubdirs();
        Q_EMIT sizeChanged();
    });
}

Properties::~Properties()
{
    if (m_sizeJob)
        m_sizeJob->kill();
}

void Properties::setUrls(const QList<QUrl> &urls)
{
    if (urls == m_urls)
        return;
    if (m_sizeJob)
        m_sizeJob->kill();
    m_urls = urls;
    m_items = KFileItemList();
    m_error.clear();
    m_size = m_files = m_folders = 0;
    m_diskSize = m_diskFree = 0;
    Q_EMIT urlsChanged();

    // Сведения о каждом — по порядку, в каком их передали.
    QList<KFileItem> items(urls.size());
    auto results = std::make_shared<QList<KFileItem>>(items);
    m_pending = urls.size();
    for (int i = 0; i < urls.size(); ++i) {
        KIO::StatJob *job = KIO::stat(urls[i], KIO::StatJob::SourceSide, details, KIO::HideProgressInfo);
        connect(job, &KJob::result, this, [this, job, i, results, urls] {
            if (urls != m_urls)
                return; // пока ждали, попросили другое
            if (job->error())
                m_error = job->errorString();
            else
                (*results)[i] = KFileItem(job->statResult(), urls[i]);
            if (--m_pending > 0)
                return;
            for (const KFileItem &item : std::as_const(*results)) {
                if (!item.isNull())
                    m_items.append(item);
            }
            itemsReady();
        });
    }
    Q_EMIT changed();
}

void Properties::itemsReady()
{
    Q_EMIT changed();
    Q_EMIT applicationChanged();
    if (m_items.isEmpty())
        return;

    startCounting();

    KIO::FileSystemFreeSpaceJob *disk = KIO::fileSystemFreeSpace(m_items.first().url());
    connect(disk, &KJob::result, this, [this, disk] {
        if (disk->error())
            return;
        m_diskSize = disk->size();
        m_diskFree = disk->availableSize();
        Q_EMIT diskChanged();
    });
}

void Properties::startCounting()
{
    bool anyDir = false;
    for (const KFileItem &item : std::as_const(m_items))
        anyDir |= item.isDir();

    if (!anyDir) {
        m_size = 0;
        for (const KFileItem &item : std::as_const(m_items))
            m_size += item.size();
        m_files = m_items.size();
        m_folders = 0;
        Q_EMIT sizeChanged();
        return;
    }

    m_sizeJob = KIO::directorySize(m_items);
    connect(m_sizeJob, &KJob::result, this, [this] {
        m_sizeTimer.stop();
        m_size = m_sizeJob->totalSize();
        m_files = m_sizeJob->totalFiles();
        m_folders = m_sizeJob->totalSubdirs();
        m_sizeJob = nullptr; // задание удалит себя само
        Q_EMIT sizeChanged();
    });
    m_sizeTimer.start();
    Q_EMIT sizeChanged();
}

QString Properties::name() const
{
    return m_items.size() == 1 ? m_items.first().text() : QString();
}

QString Properties::mimeType() const
{
    if (m_items.isEmpty())
        return {};
    const QString mime = m_items.first().mimetype();
    for (const KFileItem &item : m_items) {
        if (item.mimetype() != mime)
            return {};
    }
    return mime;
}

QString Properties::iconName() const
{
    if (m_items.isEmpty())
        return {};
    if (m_items.size() == 1 || !mimeType().isEmpty())
        return m_items.first().iconName();
    return QStringLiteral("document-multiple");
}

QString Properties::typeName() const
{
    return mimeType().isEmpty() ? QString() : m_items.first().mimeComment();
}

QUrl Properties::parentUrl() const
{
    QUrl common;
    for (const KFileItem &item : m_items) {
        const QUrl parent = item.url().adjusted(QUrl::RemoveFilename | QUrl::StripTrailingSlash);
        if (common.isEmpty())
            common = parent;
        else if (parent != common)
            return {};
    }
    return common;
}

bool Properties::isDir() const
{
    return m_items.size() == 1 && m_items.first().isDir();
}

bool Properties::canPreview() const
{
    return m_items.size() == 1 && !m_items.first().isDir() && ::canPreview(m_items.first().mimetype());
}

bool Properties::isLocal() const
{
    return !m_items.isEmpty() && m_items.first().isLocalFile();
}

QString Properties::linkTarget() const
{
    return m_items.size() == 1 && m_items.first().isLink() ? m_items.first().linkDest() : QString();
}

QDateTime Properties::modified() const
{
    return m_items.size() == 1 ? m_items.first().time(KFileItem::ModificationTime) : QDateTime();
}

QDateTime Properties::accessed() const
{
    return m_items.size() == 1 ? m_items.first().time(KFileItem::AccessTime) : QDateTime();
}

QDateTime Properties::created() const
{
    return m_items.size() == 1 ? m_items.first().time(KFileItem::CreationTime) : QDateTime();
}

int Properties::mode() const
{
    return m_items.size() == 1 ? (m_items.first().permissions() & 0777) : 0;
}

QString Properties::owner() const
{
    return m_items.size() == 1 ? m_items.first().user() : QString();
}

QString Properties::group() const
{
    return m_items.size() == 1 ? m_items.first().group() : QString();
}

bool Properties::canChangeMode() const
{
    if (m_items.size() != 1 || !m_items.first().isLocalFile() || m_items.first().isLink())
        return false;
    return ::geteuid() == 0 || m_items.first().user() == KUser().loginName();
}

QVariantMap Properties::application() const
{
    const QString mime = mimeType();
    if (mime.isEmpty() || mime == QLatin1String("inode/directory"))
        return {};
    const KService::Ptr service = KApplicationTrader::preferredService(mime);
    if (!service)
        return {};
    return {
        {QStringLiteral("id"), service->storageId()},
        {QStringLiteral("name"), service->name()},
        {QStringLiteral("icon"), service->icon()},
    };
}

void Properties::setAccess(int who, int level)
{
    if (!canChangeMode() || who < 0 || who > 2)
        return;
    const int s = shift(who);
    // У папки «читать» без права заходить бессмысленно — даём вместе.
    const int mask = (isDir() ? (R | W | X) : (R | W)) << s;
    int bits = 0;
    if (level >= 1)
        bits |= isDir() ? (R | X) : R;
    if (level >= 2)
        bits |= W;
    applyMode((mode() & ~mask) | (bits << s));
}

void Properties::setExecutable(bool executable)
{
    if (!canChangeMode() || isDir())
        return;
    const int m = mode();
    // Запускать — тем, кто может читать.
    const int x = executable ? ((m & 0444) >> 2) : 0;
    applyMode((m & ~0111) | x);
}

void Properties::applyMode(int newMode)
{
    if (newMode == mode())
        return;
    KIO::ChmodJob *job = KIO::chmod(m_items, newMode, 0777, QString(), QString(), false, KIO::HideProgressInfo);
    connect(job, &KJob::result, this, [this, job] {
        if (job->error()) {
            m_error = job->errorString();
            Q_EMIT changed();
        }
        refreshItem();
    });
}

void Properties::refreshItem()
{
    if (m_items.size() != 1)
        return;
    const QUrl url = m_items.first().url();
    KIO::StatJob *job = KIO::stat(url, KIO::StatJob::SourceSide, details, KIO::HideProgressInfo);
    connect(job, &KJob::result, this, [this, job, url] {
        if (job->error() || m_items.size() != 1 || m_items.first().url() != url)
            return;
        m_items[0] = KFileItem(job->statResult(), url);
        Q_EMIT changed();
    });
}

void Properties::setApplication(const QString &serviceId)
{
    const QString mime = mimeType();
    const KService::Ptr service = KService::serviceByStorageId(serviceId);
    if (mime.isEmpty() || !service)
        return;
    KApplicationTrader::setPreferredService(mime, service);
    Q_EMIT applicationChanged();
}
