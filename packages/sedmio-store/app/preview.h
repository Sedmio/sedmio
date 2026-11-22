#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QVariantMap>

typedef struct _GCancellable GCancellable;

// Что будет, если поставить или удалить программу, — до нажатия кнопки:
// сколько качать и сколько займёт, что доставится вместе, что программе
// Flathub разрешено, что уйдёт вместе с удаляемым пакетом. Всё без пароля
// (pacman -Sp / -Rsp, libflatpak); Flathub — по сети, до пары секунд.
class Preview : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    // {loading, ok, download, installed, extra: [имена], error,
    //  removes: [имена], removeError}
    Q_PROPERTY(QVariantMap arch READ arch NOTIFY changed)
    // {loading, ok, download, installed, runtimes: [], permissions: [{text, risky}], error}
    Q_PROPERTY(QVariantMap flathub READ flathub NOTIFY changed)

public:
    explicit Preview(QObject *parent = nullptr);
    ~Preview() override;

    QVariantMap arch() const { return m_arch; }
    QVariantMap flathub() const { return m_flathub; }

    // app — Catalog.details().
    Q_INVOKABLE void load(const QVariantMap &app);

Q_SIGNALS:
    void changed();

private:
    void loadArchInstall(const QString &package);
    void loadArchRemove(const QString &package);
    void loadFlathub(const QString &origin, const QString &ref);

    QVariantMap m_arch;
    QVariantMap m_flathub;
    QString m_key; // что сейчас смотрим (ответы на старое — мимо)
    GCancellable *m_cancellable = nullptr;
};
