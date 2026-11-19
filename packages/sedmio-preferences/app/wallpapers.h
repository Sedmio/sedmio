#pragma once

#include <QFileSystemWatcher>
#include <QObject>
#include <QVariantList>
#include <QtQml/qqmlregistration.h>

// Обои: какие картинки есть и какая выбрана. Выбор — в
// ~/.config/sedmio/wallpaper.json ({"image": "/путь"}), его читает оболочка
// (Wallpaper.qml) и сразу меняет обои. Пустой путь — обои Sedmio по умолчанию.
// Рядом — ссылка ~/.local/state/sedmio/wallpaper на ту же картинку для
// экрана блокировки и заставки.
class Wallpapers : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    // [{path, url, name}] — сначала из системы, потом из «Изображений».
    Q_PROPERTY(QVariantList images READ images NOTIFY imagesChanged)
    Q_PROPERTY(QString current READ current NOTIFY currentChanged)
    Q_PROPERTY(QString error READ error NOTIFY currentChanged)

public:
    explicit Wallpapers(QObject *parent = nullptr);

    QVariantList images() const { return m_images; }
    QString current() const { return m_current; }
    QString error() const { return m_error; }

    // path — путь или file:// адрес; "" — обои по умолчанию.
    Q_INVOKABLE void choose(const QString &path);
    Q_INVOKABLE void rescan();

Q_SIGNALS:
    void imagesChanged();
    void currentChanged();

private:
    void readCurrent();

    QVariantList m_images;
    QString m_current;
    QString m_error;
    QFileSystemWatcher m_watcher;
};
