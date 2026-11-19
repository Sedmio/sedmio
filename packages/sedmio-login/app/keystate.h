#pragma once

#include <QObject>
#include <qqmlregistration.h>

class KModifierKeyInfo;

// Залипающая клавиша-модификатор (Caps Lock): включена ли — для подсказки
// «Включён Caps Lock». Как KeyState из plasma-workspace (keyboardindicator).
class KeyState : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(int key READ key WRITE setKey NOTIFY keyChanged)
    Q_PROPERTY(bool locked READ locked NOTIFY lockedChanged)

public:
    explicit KeyState(QObject *parent = nullptr);

    int key() const;
    void setKey(int key);
    bool locked() const;

Q_SIGNALS:
    void keyChanged();
    void lockedChanged();

private:
    void update();

    KModifierKeyInfo *m_info;
    Qt::Key m_key = Qt::Key_CapsLock;
    bool m_locked = false;
};
