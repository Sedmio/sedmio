#include "keyedmodel.h"

namespace
{
constexpr int EntryRole = Qt::UserRole + 1;
}

KeyedModel::KeyedModel(const QString &keyName, QObject *parent)
    : QAbstractListModel(parent)
    , m_keyName(keyName)
{
}

int KeyedModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : int(m_items.size());
}

QVariant KeyedModel::data(const QModelIndex &index, int role) const
{
    if (role != EntryRole || !index.isValid() || index.row() >= m_items.size())
        return {};
    return m_items.at(index.row());
}

QHash<int, QByteArray> KeyedModel::roleNames() const
{
    return {{EntryRole, QByteArrayLiteral("entry")}};
}

QString KeyedModel::key(const QVariant &item) const
{
    return item.toMap().value(m_keyName).toString();
}

void KeyedModel::setItems(const QVariantList &items)
{
    bool sameKeys = items.size() == m_items.size();
    for (qsizetype i = 0; sameKeys && i < items.size(); ++i)
        sameKeys = key(items.at(i)) == key(m_items.at(i));

    if (!sameKeys) {
        const bool countChanges = items.size() != m_items.size();
        beginResetModel();
        m_items = items;
        endResetModel();
        if (countChanges)
            Q_EMIT countChanged();
        return;
    }
    for (qsizetype i = 0; i < items.size(); ++i) {
        if (items.at(i) == m_items.at(i))
            continue;
        m_items[i] = items.at(i);
        const QModelIndex at = index(int(i));
        Q_EMIT dataChanged(at, at, {EntryRole});
    }
}
