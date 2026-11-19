#include "keystate.h"

#include <KModifierKeyInfo>

KeyState::KeyState(QObject *parent)
    : QObject(parent)
    , m_info(new KModifierKeyInfo(this))
{
    connect(m_info, &KModifierKeyInfo::keyLocked, this, [this](Qt::Key key, bool) {
        if (key == m_key)
            update();
    });
    update();
}

int KeyState::key() const
{
    return m_key;
}

void KeyState::setKey(int key)
{
    if (m_key == key)
        return;
    m_key = Qt::Key(key);
    Q_EMIT keyChanged();
    update();
}

bool KeyState::locked() const
{
    return m_locked;
}

void KeyState::update()
{
    const bool locked = m_info->isKeyLocked(m_key);
    if (locked != m_locked) {
        m_locked = locked;
        Q_EMIT lockedChanged();
    }
}
