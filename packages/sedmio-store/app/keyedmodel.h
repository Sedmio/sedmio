#pragma once

#include <QAbstractListModel>
#include <QQmlEngine>
#include <QVariantList>

// Список для Repeater/ListView, который не пересоздаёт строки зря.
// Repeater на JS-массиве при любой перемене создаёт все строки заново:
// пропадает фокус из поля, сбрасывается прокрутка, кнопки мигают. Здесь
// строки опознаются по ключу: тот же набор в том же порядке — меняются
// только данные (dataChanged), иначе — полная замена.
//
// В делегате: required property var entry (QVariantMap строки).
class KeyedModel : public QAbstractListModel
{
    Q_OBJECT
    QML_ANONYMOUS
    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)

public:
    explicit KeyedModel(const QString &keyName, QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    void setItems(const QVariantList &items);
    QVariantList items() const { return m_items; }

Q_SIGNALS:
    void countChanged();

private:
    QString key(const QVariant &item) const;

    QString m_keyName;
    QVariantList m_items;
};
