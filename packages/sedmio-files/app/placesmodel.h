#pragma once

#include <QSortFilterProxyModel>
#include <QUrl>
#include <QtQml/qqmlregistration.h>

class KFilePlacesModel;

// Места слева: папки пользователя и корзина, сеть, диски и флешки.
// Берётся из KFilePlacesModel (тот же список, что в Dolphin и окнах
// открытия файлов), без «Недавних», поиска и меток.
class PlacesModel : public QSortFilterProxyModel
{
    Q_OBJECT
    QML_ELEMENT

public:
    enum Roles {
        NameRole = Qt::UserRole + 1,
        UrlRole,
        IconRole,
        SectionRole,
        IsDeviceRole,
        SetupNeededRole,
        EjectableRole,
    };

    explicit PlacesModel(QObject *parent = nullptr);

    QHash<int, QByteArray> roleNames() const override;
    QVariant data(const QModelIndex &index, int role) const override;

    // Подключить диск или флешку; потом setupDone.
    Q_INVOKABLE void setup(int row);
    // Безопасно извлечь.
    Q_INVOKABLE void eject(int row);
    // Строка места, в котором лежит адрес (для подсветки), или -1.
    Q_INVOKABLE int rowFor(const QUrl &url) const;

Q_SIGNALS:
    void setupDone(const QUrl &url, bool success);
    void errorMessage(const QString &message);

protected:
    bool filterAcceptsRow(int sourceRow, const QModelIndex &sourceParent) const override;

private:
    KFilePlacesModel *m_places;
};
