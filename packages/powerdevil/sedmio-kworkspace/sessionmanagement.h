// SessionManagement для powerdevil без plasma-workspace (см. CMakeLists.txt).
// Тот же интерфейс, что у libkworkspace; powerdevil зовёт только can*(),
// сон и гибернацию, requestShutdown, requestLogoutPrompt и lock.
#pragma once

#include <QObject>

class SessionManagement : public QObject
{
    Q_OBJECT

public:
    enum class State {
        Loading,
        Ready,
        Error,
    };
    Q_ENUM(State)

    enum class ConfirmationMode {
        Default = -1,
        Skip = 0,
        ForcePrompt = 1,
    };
    Q_ENUM(ConfirmationMode)

    explicit SessionManagement(QObject *parent = nullptr);

    State state() const;

    bool canShutdown() const;
    bool canReboot() const;
    bool canLogout() const;
    bool canSuspend() const;
    bool canHybridSuspend() const;
    bool canHibernate() const;
    bool canSuspendThenHibernate() const;
    bool canSwitchUser() const;
    bool canLock() const;
    bool canSaveSession() const;

public Q_SLOTS:
    void requestShutdown(ConfirmationMode = ConfirmationMode::Default);
    void requestReboot(ConfirmationMode = ConfirmationMode::Default);
    void requestLogout(ConfirmationMode = ConfirmationMode::Default);

    void requestLogoutPrompt();

    void suspend();
    void hybridSuspend();
    void hibernate();
    void suspendThenHibernate();

    void switchUser();
    void lock();

    void saveSession();
};
