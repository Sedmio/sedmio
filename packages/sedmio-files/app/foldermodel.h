#pragma once

#include <KDirSortFilterProxyModel>
#include <QDateTime>
#include <QSet>
#include <QUrl>
#include <QtQml/qqmlregistration.h>

class KDirModel;
class KFileItem;

// Содержимое одной папки для QML: список из KIO (локальные папки, корзина,
// сеть, флешки), папки сначала, имена в естественном порядке («2» раньше
// «10»). Здесь же выделение: какие строки выбраны, хранится по адресам,
// так что переживает сортировку и фильтр.
class FolderModel : public KDirSortFilterProxyModel
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(QUrl url READ url WRITE setUrl NOTIFY urlChanged)
    Q_PROPERTY(bool showHidden READ showHidden WRITE setShowHidden NOTIFY showHiddenChanged)
    // Показывать только то, в имени чего есть эта строка (без учёта регистра).
    Q_PROPERTY(QString filter READ filter WRITE setFilter NOTIFY filterChanged)
    // name, size, date, type
    Q_PROPERTY(QString sortBy READ sortBy WRITE setSortBy NOTIFY sortChanged)
    Q_PROPERTY(bool descending READ descending WRITE setDescending NOTIFY sortChanged)
    Q_PROPERTY(int count READ count NOTIFY countChanged)
    Q_PROPERTY(bool loading READ loading NOTIFY loadingChanged)
    // Почему папку не открыть (нет такой, нет прав); пусто, если открылась.
    Q_PROPERTY(QString error READ error NOTIFY errorChanged)
    // Можно ли в эту папку что-то положить.
    Q_PROPERTY(bool writable READ writable NOTIFY loadingChanged)
    Q_PROPERTY(bool isTrash READ isTrash NOTIFY urlChanged)
    Q_PROPERTY(int selectedCount READ selectedCount NOTIFY selectionChanged)
    // Сколько весят выбранные файлы (папки не считаются).
    Q_PROPERTY(qreal selectedSize READ selectedSize NOTIFY selectionChanged)

public:
    enum Roles {
        NameRole = Qt::UserRole + 1,
        UrlRole,
        IconRole,
        IsDirRole,
        IsLinkRole,
        IsHiddenRole,
        SizeRole,
        ModifiedRole,
        TypeRole,
        MimeRole,
        CanPreviewRole,
        SelectedRole,
        ChildCountRole,
    };

    explicit FolderModel(QObject *parent = nullptr);

    QHash<int, QByteArray> roleNames() const override;
    QVariant data(const QModelIndex &index, int role) const override;

    QUrl url() const;
    void setUrl(const QUrl &url);
    bool showHidden() const { return m_showHidden; }
    void setShowHidden(bool show);
    QString filter() const { return m_filter; }
    void setFilter(const QString &filter);
    QString sortBy() const { return m_sortBy; }
    void setSortBy(const QString &sortBy);
    bool descending() const { return m_descending; }
    void setDescending(bool descending);
    int count() const { return rowCount(); }
    bool loading() const { return m_loading; }
    QString error() const { return m_error; }
    bool writable() const;
    bool isTrash() const { return url().scheme() == QLatin1String("trash"); }
    int selectedCount() const { return m_selected.size(); }
    qreal selectedSize() const;

    Q_INVOKABLE QUrl urlAt(int row) const;
    Q_INVOKABLE QString nameAt(int row) const;
    Q_INVOKABLE QString mimeAt(int row) const;
    Q_INVOKABLE bool isDirAt(int row) const;
    // Строка с таким именем или -1.
    Q_INVOKABLE int rowOf(const QString &name) const;
    Q_INVOKABLE void reload();

    // Выделение. mode: 0 — только эта, 1 — переключить эту, 2 — от
    // предыдущей до этой, 3 — добавить эту.
    Q_INVOKABLE void select(int row, int mode = 0);
    // Выделить эти адреса (что есть в папке); вернёт первую строку или -1.
    Q_INVOKABLE int selectUrls(const QList<QUrl> &urls);
    Q_INVOKABLE void selectAll();
    Q_INVOKABLE void clearSelection();
    Q_INVOKABLE bool isSelected(int row) const;
    Q_INVOKABLE QList<QUrl> selectedUrls() const;
    // Только файлы из выбранного (без папок).
    Q_INVOKABLE QList<QUrl> selectedFiles() const;
    // Первая выбранная строка сверху или -1.
    Q_INVOKABLE int firstSelected() const;

Q_SIGNALS:
    void urlChanged();
    void showHiddenChanged();
    void filterChanged();
    void sortChanged();
    void countChanged();
    void loadingChanged();
    void errorChanged();
    void selectionChanged();

protected:
    bool filterAcceptsRow(int sourceRow, const QModelIndex &sourceParent) const override;

private:
    KFileItem itemAt(const QModelIndex &index) const;
    void applySort();
    void setLoading(bool loading);
    void setError(const QString &error);
    void selectionUpdated();
    int localChildCount(const KFileItem &item) const;

    KDirModel *m_dirModel;
    bool m_showHidden = false;
    QString m_filter;
    QString m_sortBy = QStringLiteral("name");
    bool m_descending = false;
    bool m_loading = false;
    QString m_error;
    QSet<QUrl> m_selected;
    int m_anchor = -1; // откуда тянется выделение с Shift
    mutable QHash<QUrl, std::pair<QDateTime, int>> m_childCounts;
};
