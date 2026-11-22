#pragma once

#include <QDBusAbstractAdaptor>
#include <QObject>
#include <QPointer>
#include <QQmlEngine>
#include <QQuickWindow>

// Одно окно «Программ» на сеанс (org.sedmio.Store): повторный запуск
// поднимает открытое, а «sedmio-store <id>» (из меню программ — «Открыть
// в магазине») открывает в нём карточку программы.
class StoreHost : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

public:
    static StoreHost *instance();
    static StoreHost *create(QQmlEngine *, QJSEngine *) { return instance(); }

    void setWindow(QQuickWindow *window) { m_window = window; }
    bool registerOnBus();
    static bool forward(const QString &appId);

    // «Параметры» → «Обновление»: базы пакетов устарели, сначала — система.
    Q_INVOKABLE void openSystemUpdates();

    // Что открыть при запуске (sedmio-store <id>).
    Q_INVOKABLE QString takeStartApp();
    void setStartApp(const QString &appId) { m_startApp = appId; }

public Q_SLOTS:
    void show(const QString &token, const QString &appId);

Q_SIGNALS:
    void openApp(const QString &appId);

private:
    explicit StoreHost(QObject *parent = nullptr);
    QPointer<QQuickWindow> m_window;
    QString m_startApp;
};

class StoreAdaptor : public QDBusAbstractAdaptor
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.sedmio.Store")

public:
    explicit StoreAdaptor(StoreHost *host)
        : QDBusAbstractAdaptor(host)
        , m_host(host)
    {
    }

public Q_SLOTS:
    void Show(const QString &token, const QString &appId) { m_host->show(token, appId); }

private:
    StoreHost *m_host;
};
