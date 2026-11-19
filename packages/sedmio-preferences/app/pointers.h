#pragma once

#include <QDBusContext>
#include <QMap>
#include <QSet>
#include <QObject>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

// Мыши и тачпады — через KWin (org.kde.KWin, /org/kde/KWin/InputDevice/*):
// он применяет параметры libinput и сам сохраняет их в kcminputrc, как для
// модуля параметров KDE. Правка идёт на все устройства одного рода разом
// (две мыши — обе), как в Windows; показываем значения первого.
class Pointers : public QObject, protected QDBusContext
{
    Q_OBJECT
    QML_ELEMENT

    // Свойства первого устройства (имена — как у KWin: pointerAcceleration,
    // naturalScroll, supportsLeftHanded…) и present — есть ли такие вообще.
    Q_PROPERTY(QVariantMap mouse READ mouse NOTIFY changed)
    Q_PROPERTY(QVariantMap touchpad READ touchpad NOTIFY changed)
    Q_PROPERTY(QString error READ error NOTIFY changed)
    // Размер указателя, пикселей (kcminputrc [Mouse] cursorSize, как у
    // KDE; KWin и GTK через kde-gtk-config подхватывают сразу).
    Q_PROPERTY(int cursorSize READ cursorSize NOTIFY cursorSizeChanged)

public:
    explicit Pointers(QObject *parent = nullptr);

    QVariantMap mouse() const { return summary(false); }
    QVariantMap touchpad() const { return summary(true); }
    QString error() const { return m_error; }
    int cursorSize() const;
    Q_INVOKABLE void setCursorSize(int size);

    // kind: "mouse" | "touchpad"; name — свойство KWin.
    Q_INVOKABLE void set(const QString &kind, const QString &name, const QVariant &value);

Q_SIGNALS:
    void changed();
    void cursorSizeChanged();

private Q_SLOTS:
    void reload();
    void onPropertiesChanged(const QString &interface, const QVariantMap &changed, const QStringList &invalidated);

private:
    QVariantMap summary(bool touchpad) const;
    QStringList devicesOf(bool touchpad) const;

    QMap<QString, QVariantMap> m_devices; // sysName → свойства
    QSet<QString> m_watched;              // на чьи изменения уже подписаны
    QString m_error;
};
