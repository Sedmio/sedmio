#pragma once

#include <QObject>
#include <qqmlregistration.h>

// Сон с экрана блокировки — через logind, как SessionManagement из
// plasma-workspace.
class Power : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(bool canSuspend READ canSuspend CONSTANT)

public:
    explicit Power(QObject *parent = nullptr);

    bool canSuspend() const;
    Q_INVOKABLE void suspend();

private:
    bool m_canSuspend = false;
};
