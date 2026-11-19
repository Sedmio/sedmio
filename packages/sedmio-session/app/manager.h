#pragma once

#include <QList>
#include <QObject>
#include <QPointer>
#include <QQmlEngine>
#include <QQuickWindow>
#include <QVariantMap>

class QScreen;

// Выход из сеанса, выключение и перезагрузка — вместо ksmserver,
// plasma-shutdown и ksmserver-logout-greeter из Plasma.
//
// На шине под теми же именами, что у Plasma, — их зовут программы KDE,
// powerdevil (кнопка питания), KWin-скрипт sedmio-windowkeys (Alt+F4 на
// пустом столе), оболочка:
//   org.kde.LogoutPrompt /LogoutPrompt — показать экран «Что сделать?»;
//   org.kde.Shutdown /Shutdown — выйти, выключить, перезагрузить сразу.
// org.kde.Shutdown занят только пока идёт выход (как у plasma-shutdown):
// powerdevil по нему не усыпляет компьютер. Постоянно — своё имя
// org.sedmio.SessionManager с теми же объектами (так зовут оболочка и
// powerdevil).
//
// Выход: KWin закрывает окна (программы могут спросить «сохранить?» и
// отменить выход), затем logind выключает или перезагружает, а для
// выхода останавливается graphical-session.target (sedmio-session ждёт
// именно этого).
class Manager : public QObject
{
    Q_OBJECT
    // Для QML экрана: есть ли диспетчер задач (кнопка на экране).
    Q_PROPERTY(bool taskManagerAvailable READ taskManagerAvailable CONSTANT)

public:
    // Как KWorkSpace::ShutdownType: этого ждёт QML экрана (sdtype).
    enum Type {
        Default = -1,
        None = 0,
        Reboot = 1,
        Halt = 2,
        Logout = 3,
    };

    explicit Manager(QObject *parent = nullptr);

    bool registerOnBus();
    bool taskManagerAvailable() const;

    void prompt(Type type);
    void startLogout(Type type);

    Q_INVOKABLE bool launchTaskManager();

    // Сигналы экрана (имена — как у ksmserver-logout-greeter).
    Q_INVOKABLE void logoutRequested();
    Q_INVOKABLE void haltRequested();
    Q_INVOKABLE void rebootRequested();
    Q_INVOKABLE void suspendRequested(int method);
    Q_INVOKABLE void lockScreenRequested();
    Q_INVOKABLE void cancelRequested();

private:
    void showOn(QScreen *screen);
    void closePrompt();
    void finish();
    void cancelled();
    QString logind(const QString &method) const;

    QQmlEngine m_engine;
    QList<QPointer<QQuickWindow>> m_windows;
    Type m_logoutType = None;
};

// org.kde.LogoutPrompt — как у ksmserver-logout-greeter.
class LogoutPrompt : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.kde.LogoutPrompt")

public:
    explicit LogoutPrompt(Manager *manager);

public Q_SLOTS:
    Q_SCRIPTABLE void promptLogout();
    Q_SCRIPTABLE void promptShutDown();
    Q_SCRIPTABLE void promptReboot();
    Q_SCRIPTABLE void promptAll();

private:
    Manager *m_manager;
};

// org.kde.Shutdown — как у plasma-shutdown.
class Shutdown : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.kde.Shutdown")

public:
    explicit Shutdown(Manager *manager);

public Q_SLOTS:
    Q_SCRIPTABLE void logout();
    Q_SCRIPTABLE void logoutAndShutdown();
    Q_SCRIPTABLE void logoutAndReboot();
    // Сеанс не запоминаем (как Windows) — нечего сохранять.
    Q_SCRIPTABLE void saveSession();

private:
    Manager *m_manager;
};
