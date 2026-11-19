#include "pointers.h"

#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusVariant>

namespace
{
const QString service = QStringLiteral("org.kde.KWin");
const QString managerPath = QStringLiteral("/org/kde/KWin/InputDevice");
const QString managerInterface = QStringLiteral("org.kde.KWin.InputDeviceManager");
const QString deviceInterface = QStringLiteral("org.kde.KWin.InputDevice");
const QString propertiesInterface = QStringLiteral("org.freedesktop.DBus.Properties");

QDBusConnection bus()
{
    return QDBusConnection::sessionBus();
}

QVariant getProperty(const QString &path, const QString &interface, const QString &name)
{
    auto message = QDBusMessage::createMethodCall(service, path, propertiesInterface, QStringLiteral("Get"));
    message << interface << name;
    const QDBusMessage reply = bus().call(message, QDBus::Block, 3000);
    if (reply.type() != QDBusMessage::ReplyMessage || reply.arguments().isEmpty())
        return {};
    return reply.arguments().constFirst().value<QDBusVariant>().variant();
}

QVariantMap allProperties(const QString &path)
{
    auto message = QDBusMessage::createMethodCall(service, path, propertiesInterface, QStringLiteral("GetAll"));
    message << deviceInterface;
    const QDBusMessage reply = bus().call(message, QDBus::Block, 3000);
    if (reply.type() != QDBusMessage::ReplyMessage || reply.arguments().isEmpty())
        return {};
    return qdbus_cast<QVariantMap>(reply.arguments().constFirst());
}

// Каким флагом KWin говорит, что свойство у устройства есть.
QString supportFlag(const QString &name)
{
    if (name == QLatin1String("scrollFactor"))
        return {}; // есть у всех
    if (name == QLatin1String("tapToClick"))
        return QStringLiteral("tapFingerCount");
    if (name == QLatin1String("enabled"))
        return QStringLiteral("supportsDisableEvents");
    return QStringLiteral("supports") + name.at(0).toUpper() + name.mid(1);
}

bool supports(const QVariantMap &device, const QString &name)
{
    const QString flag = supportFlag(name);
    if (flag.isEmpty())
        return true;
    const QVariant value = device.value(flag);
    return value.typeId() == QMetaType::Int ? value.toInt() > 0 : value.toBool();
}
} // namespace

Pointers::Pointers(QObject *parent)
    : QObject(parent)
{
    bus().connect(service, managerPath, managerInterface, QStringLiteral("deviceAdded"), this, SLOT(reload()));
    bus().connect(service, managerPath, managerInterface, QStringLiteral("deviceRemoved"), this, SLOT(reload()));
    reload();
}

void Pointers::reload()
{
    const QStringList names = getProperty(managerPath, managerInterface, QStringLiteral("devicesSysNames")).toStringList();
    QMap<QString, QVariantMap> devices;
    for (const QString &name : names) {
        const QString path = managerPath + QLatin1Char('/') + name;
        QVariantMap properties = allProperties(path);
        if (!properties.value(QStringLiteral("pointer")).toBool() && !properties.value(QStringLiteral("touchpad")).toBool())
            continue;
        devices.insert(name, properties);
        if (!m_watched.contains(path)) {
            m_watched.insert(path);
            bus().connect(service, path, propertiesInterface, QStringLiteral("PropertiesChanged"), this,
                          SLOT(onPropertiesChanged(QString, QVariantMap, QStringList)));
        }
    }
    m_devices = devices;
    m_error = names.isEmpty() ? QStringLiteral("KWin не отвечает: параметры мыши сейчас недоступны.") : QString();
    Q_EMIT changed();
}

void Pointers::onPropertiesChanged(const QString &interface, const QVariantMap &changedProperties, const QStringList &)
{
    if (interface != deviceInterface)
        return;
    const QString path = message().path();
    const QString name = path.section(QLatin1Char('/'), -1);
    if (!m_devices.contains(name))
        return;
    QVariantMap &device = m_devices[name];
    for (auto it = changedProperties.cbegin(); it != changedProperties.cend(); ++it)
        device.insert(it.key(), it.value());
    Q_EMIT changed();
}

QStringList Pointers::devicesOf(bool touchpad) const
{
    QStringList list;
    for (auto it = m_devices.cbegin(); it != m_devices.cend(); ++it) {
        if (it.value().value(QStringLiteral("touchpad")).toBool() == touchpad)
            list.append(it.key());
    }
    return list;
}

QVariantMap Pointers::summary(bool touchpad) const
{
    // Первое устройство, у которого есть ускорение (у мыши это настоящая
    // мышь, а не планшет QEMU или «указатель» клавиатуры), иначе любое.
    const QStringList names = devicesOf(touchpad);
    QVariantMap result;
    for (const QString &name : names) {
        if (m_devices.value(name).value(QStringLiteral("supportsPointerAcceleration")).toBool()) {
            result = m_devices.value(name);
            break;
        }
    }
    if (result.isEmpty() && !names.isEmpty())
        result = m_devices.value(names.constFirst());
    result.insert(QStringLiteral("present"), !names.isEmpty());
    return result;
}

void Pointers::set(const QString &kind, const QString &name, const QVariant &value)
{
    const bool touchpad = kind == QLatin1String("touchpad");
    bool applied = false;
    for (const QString &device : devicesOf(touchpad)) {
        if (!supports(m_devices.value(device), name))
            continue;
        auto message = QDBusMessage::createMethodCall(service, managerPath + QLatin1Char('/') + device, propertiesInterface,
                                                      QStringLiteral("Set"));
        message << deviceInterface << name << QVariant::fromValue(QDBusVariant(value));
        const QDBusMessage reply = bus().call(message, QDBus::Block, 3000);
        if (reply.type() == QDBusMessage::ErrorMessage) {
            m_error = QStringLiteral("Не удалось изменить: %1").arg(reply.errorMessage());
            Q_EMIT changed();
            continue;
        }
        applied = true;
        // Перечитываем целиком: одно свойство тянет за собой другие
        // (профиль ускорения — это пара Adaptive/Flat).
        const QVariantMap fresh = allProperties(managerPath + QLatin1Char('/') + device);
        if (!fresh.isEmpty())
            m_devices[device] = fresh;
        else
            m_devices[device].insert(name, value);
    }
    if (applied) {
        m_error.clear();
        Q_EMIT changed();
    }
}
