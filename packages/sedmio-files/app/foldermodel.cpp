#include "foldermodel.h"
#include "images.h"

#include <KDirLister>
#include <KDirModel>
#include <KFileItem>
#include <KIO/Job>
#include <KIO/PreviewJob>

#include <QFile>

#include <dirent.h>

FolderModel::FolderModel(QObject *parent)
    : KDirSortFilterProxyModel(parent)
    , m_dirModel(new KDirModel(this))
{
    setSourceModel(m_dirModel);
    setSortFoldersFirst(true);
    setDynamicSortFilter(true);
    setSortCaseSensitivity(Qt::CaseInsensitive);
    applySort();

    KDirLister *lister = m_dirModel->dirLister();
    lister->setAutoErrorHandlingEnabled(false);
    lister->setShowHiddenFiles(false);

    connect(lister, &KCoreDirLister::started, this, [this] {
        setError(QString());
        setLoading(true);
    });
    connect(lister, &KCoreDirLister::completed, this, [this] {
        setLoading(false);
    });
    connect(lister, &KCoreDirLister::canceled, this, [this] {
        setLoading(false);
    });
    connect(lister, &KCoreDirLister::jobError, this, [this](KIO::Job *job) {
        setError(job->errorString());
        setLoading(false);
    });

    auto countChanged = [this] {
        Q_EMIT this->countChanged();
    };
    connect(this, &QAbstractItemModel::rowsInserted, this, countChanged);
    connect(this, &QAbstractItemModel::rowsRemoved, this, countChanged);
    connect(this, &QAbstractItemModel::modelReset, this, countChanged);
    connect(this, &QAbstractItemModel::layoutChanged, this, countChanged);

    // Удалённые из папки — и из выделения.
    connect(this, &QAbstractItemModel::rowsAboutToBeRemoved, this, [this](const QModelIndex &, int first, int last) {
        bool changed = false;
        for (int row = first; row <= last; ++row)
            changed |= m_selected.remove(urlAt(row));
        if (changed)
            QMetaObject::invokeMethod(this, &FolderModel::selectionChanged, Qt::QueuedConnection);
    });
    connect(this, &QAbstractItemModel::modelReset, this, [this] {
        m_anchor = -1;
        if (!m_selected.isEmpty()) {
            m_selected.clear();
            Q_EMIT selectionChanged();
        }
    });
}

QHash<int, QByteArray> FolderModel::roleNames() const
{
    return {
        {NameRole, "name"},
        {UrlRole, "url"},
        {IconRole, "iconName"},
        {IsDirRole, "isDir"},
        {IsLinkRole, "isLink"},
        {IsHiddenRole, "isHidden"},
        {SizeRole, "size"},
        {ModifiedRole, "modified"},
        {TypeRole, "typeText"},
        {MimeRole, "mimeType"},
        {CanPreviewRole, "canPreview"},
        {SelectedRole, "selected"},
        {ChildCountRole, "childCount"},
    };
}

KFileItem FolderModel::itemAt(const QModelIndex &index) const
{
    return m_dirModel->itemForIndex(mapToSource(index));
}

QVariant FolderModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || role < NameRole)
        return KDirSortFilterProxyModel::data(index, role);

    const KFileItem item = itemAt(index);
    if (item.isNull())
        return {};

    switch (role) {
    case NameRole:
        return item.text();
    case UrlRole:
        return item.url();
    case IconRole:
        return item.iconName();
    case IsDirRole:
        return item.isDir();
    case IsLinkRole:
        return item.isLink();
    case IsHiddenRole:
        return item.isHidden();
    case SizeRole:
        return item.isDir() ? -1.0 : static_cast<qreal>(item.size());
    case ModifiedRole:
        return item.time(KFileItem::ModificationTime);
    case TypeRole:
        return item.mimeComment();
    case MimeRole:
        return item.mimetype();
    case CanPreviewRole:
        return !item.isDir() && canPreview(item.mimetype());
    case SelectedRole:
        return m_selected.contains(item.url());
    case ChildCountRole:
        if (!item.isDir())
            return -1;
        if (item.isLocalFile())
            return localChildCount(item);
        return mapToSource(index).data(KDirModel::ChildCountRole);
    }
    return {};
}

QUrl FolderModel::url() const
{
    return m_dirModel->dirLister()->url();
}

void FolderModel::setUrl(const QUrl &url)
{
    const QUrl clean = url.adjusted(QUrl::StripTrailingSlash | QUrl::NormalizePathSegments);
    if (clean == this->url() && m_error.isEmpty())
        return;

    m_selected.clear();
    m_anchor = -1;
    m_childCounts.clear();
    m_filter.clear();
    Q_EMIT filterChanged();
    Q_EMIT selectionChanged();

    m_dirModel->openUrl(clean);
    Q_EMIT urlChanged();
}

void FolderModel::reload()
{
    m_dirModel->openUrl(url(), KDirModel::Reload);
}

void FolderModel::setShowHidden(bool show)
{
    if (m_showHidden == show)
        return;
    m_showHidden = show;
    m_dirModel->dirLister()->setShowHiddenFiles(show);
    m_dirModel->dirLister()->emitChanges();
    Q_EMIT showHiddenChanged();
}

void FolderModel::setFilter(const QString &filter)
{
    if (m_filter == filter)
        return;
    beginFilterChange();
    m_filter = filter;
    endFilterChange(QSortFilterProxyModel::Direction::Rows);
    Q_EMIT filterChanged();
}

bool FolderModel::filterAcceptsRow(int sourceRow, const QModelIndex &sourceParent) const
{
    if (m_filter.isEmpty())
        return true;
    const QModelIndex index = m_dirModel->index(sourceRow, 0, sourceParent);
    return m_dirModel->itemForIndex(index).text().contains(m_filter, Qt::CaseInsensitive);
}

void FolderModel::setSortBy(const QString &sortBy)
{
    if (m_sortBy == sortBy)
        return;
    m_sortBy = sortBy;
    applySort();
    Q_EMIT sortChanged();
}

void FolderModel::setDescending(bool descending)
{
    if (m_descending == descending)
        return;
    m_descending = descending;
    applySort();
    Q_EMIT sortChanged();
}

void FolderModel::applySort()
{
    int column = KDirModel::Name;
    if (m_sortBy == QLatin1String("size"))
        column = KDirModel::Size;
    else if (m_sortBy == QLatin1String("date"))
        column = KDirModel::ModifiedTime;
    else if (m_sortBy == QLatin1String("type"))
        column = KDirModel::Type;
    sort(column, m_descending ? Qt::DescendingOrder : Qt::AscendingOrder);
}

void FolderModel::setLoading(bool loading)
{
    if (m_loading == loading)
        return;
    m_loading = loading;
    Q_EMIT loadingChanged();
}

void FolderModel::setError(const QString &error)
{
    if (m_error == error)
        return;
    m_error = error;
    Q_EMIT errorChanged();
}

bool FolderModel::writable() const
{
    const KFileItem root = m_dirModel->dirLister()->rootItem();
    return !root.isNull() && root.isWritable();
}

qreal FolderModel::selectedSize() const
{
    qreal size = 0;
    for (int row = 0; row < rowCount(); ++row) {
        const KFileItem item = itemAt(index(row, 0));
        if (!item.isDir() && m_selected.contains(item.url()))
            size += static_cast<qreal>(item.size());
    }
    return size;
}

QUrl FolderModel::urlAt(int row) const
{
    if (row < 0 || row >= rowCount())
        return {};
    return itemAt(index(row, 0)).url();
}

QString FolderModel::nameAt(int row) const
{
    if (row < 0 || row >= rowCount())
        return {};
    return itemAt(index(row, 0)).text();
}

QVariantMap FolderModel::infoAt(int row) const
{
    if (row < 0 || row >= rowCount())
        return {};
    const QModelIndex idx = index(row, 0);
    QVariantMap info;
    const QHash<int, QByteArray> roles = roleNames();
    for (int role : {NameRole, UrlRole, IconRole, IsDirRole, SizeRole, ModifiedRole, TypeRole, MimeRole, CanPreviewRole, ChildCountRole})
        info.insert(QString::fromLatin1(roles.value(role)), data(idx, role));
    return info;
}

QString FolderModel::mimeAt(int row) const
{
    if (row < 0 || row >= rowCount())
        return {};
    return itemAt(index(row, 0)).mimetype();
}

bool FolderModel::isDirAt(int row) const
{
    if (row < 0 || row >= rowCount())
        return false;
    return itemAt(index(row, 0)).isDir();
}

int FolderModel::rowOf(const QString &name) const
{
    for (int row = 0; row < rowCount(); ++row) {
        if (itemAt(index(row, 0)).text() == name)
            return row;
    }
    return -1;
}

void FolderModel::selectionUpdated()
{
    if (rowCount() > 0)
        Q_EMIT dataChanged(index(0, 0), index(rowCount() - 1, 0), {SelectedRole});
    Q_EMIT selectionChanged();
}

void FolderModel::select(int row, int mode)
{
    const QUrl url = urlAt(row);
    if (url.isEmpty())
        return;

    switch (mode) {
    case 0:
        m_selected = {url};
        m_anchor = row;
        break;
    case 1:
        if (!m_selected.remove(url))
            m_selected.insert(url);
        m_anchor = row;
        break;
    case 2: {
        const int from = m_anchor >= 0 && m_anchor < rowCount() ? m_anchor : row;
        m_selected.clear();
        for (int r = qMin(from, row); r <= qMax(from, row); ++r)
            m_selected.insert(urlAt(r));
        break;
    }
    case 3:
        m_selected.insert(url);
        m_anchor = row;
        break;
    }
    selectionUpdated();
}

int FolderModel::selectUrls(const QList<QUrl> &urls)
{
    QSet<QUrl> wanted;
    for (const QUrl &url : urls)
        wanted.insert(url.adjusted(QUrl::StripTrailingSlash | QUrl::NormalizePathSegments));

    m_selected.clear();
    int first = -1;
    for (int row = 0; row < rowCount(); ++row) {
        const QUrl url = urlAt(row);
        if (!wanted.contains(url.adjusted(QUrl::StripTrailingSlash)))
            continue;
        m_selected.insert(url);
        if (first < 0)
            first = row;
    }
    m_anchor = first;
    selectionUpdated();
    return first;
}

void FolderModel::selectRows(const QList<int> &rows, const QList<QUrl> &base)
{
    QSet<QUrl> selected(base.cbegin(), base.cend());
    for (int row : rows) {
        const QUrl url = urlAt(row);
        if (!url.isEmpty())
            selected.insert(url);
    }
    if (selected == m_selected)
        return;
    m_selected = selected;
    selectionUpdated();
}

void FolderModel::selectAll()
{
    m_selected.clear();
    for (int row = 0; row < rowCount(); ++row)
        m_selected.insert(urlAt(row));
    selectionUpdated();
}

void FolderModel::clearSelection()
{
    m_anchor = -1;
    if (m_selected.isEmpty())
        return;
    m_selected.clear();
    selectionUpdated();
}

bool FolderModel::isSelected(int row) const
{
    return m_selected.contains(urlAt(row));
}

QList<QUrl> FolderModel::selectedUrls() const
{
    // В порядке показа, а не в порядке выбора.
    QList<QUrl> urls;
    for (int row = 0; row < rowCount() && urls.size() < m_selected.size(); ++row) {
        const QUrl url = urlAt(row);
        if (m_selected.contains(url))
            urls.append(url);
    }
    return urls;
}

QList<QUrl> FolderModel::selectedFiles() const
{
    QList<QUrl> urls;
    for (int row = 0; row < rowCount(); ++row) {
        const KFileItem item = itemAt(index(row, 0));
        if (!item.isDir() && m_selected.contains(item.url()))
            urls.append(item.url());
    }
    return urls;
}

int FolderModel::firstSelected() const
{
    for (int row = 0; row < rowCount(); ++row) {
        if (m_selected.contains(urlAt(row)))
            return row;
    }
    return -1;
}

// KDirModel считает содержимое подпапки один раз и больше не обновляет:
// скопировали в папку — а в списке всё ещё «0 объектов». Считаем сами и
// пересчитываем, когда у папки меняется время изменения.
int FolderModel::localChildCount(const KFileItem &item) const
{
    const QDateTime modified = item.time(KFileItem::ModificationTime);
    const auto cached = m_childCounts.constFind(item.url());
    if (cached != m_childCounts.cend() && cached->first == modified)
        return cached->second;

    int count = -1;
    if (DIR *dir = opendir(QFile::encodeName(item.localPath()).constData())) {
        count = 0;
        while (const dirent *entry = readdir(dir)) {
            const char *name = entry->d_name;
            if (name[0] == '.' && (name[1] == 0 || (name[1] == '.' && name[2] == 0)))
                continue;
            ++count;
        }
        closedir(dir);
    }
    m_childCounts.insert(item.url(), {modified, count});
    return count;
}
