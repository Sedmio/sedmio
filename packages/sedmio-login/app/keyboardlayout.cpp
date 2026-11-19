#include "keyboardlayout.h"

#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusMetaType>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>

namespace
{
const QString kService = QStringLiteral("org.kde.keyboard");
const QString kPath = QStringLiteral("/Layouts");
const QString kInterface = QStringLiteral("org.kde.KeyboardLayouts");

struct LayoutNames {
    QString shortName;
    QString displayName;
    QString longName;
};

const QDBusArgument &operator>>(const QDBusArgument &argument, LayoutNames &names)
{
    argument.beginStructure();
    argument >> names.shortName >> names.displayName >> names.longName;
    argument.endStructure();
    return argument;
}

QDBusArgument &operator<<(QDBusArgument &argument, const LayoutNames &names)
{
    argument.beginStructure();
    argument << names.shortName << names.displayName << names.longName;
    argument.endStructure();
    return argument;
}

QDBusMessage call(const QString &method)
{
    return QDBusMessage::createMethodCall(kService, kPath, kInterface, method);
}
} // namespace

Q_DECLARE_METATYPE(LayoutNames)

KeyboardLayout::KeyboardLayout(QObject *parent)
    : QObject(parent)
{
    qDBusRegisterMetaType<LayoutNames>();
    qDBusRegisterMetaType<QList<LayoutNames>>();
    QDBusConnection bus = QDBusConnection::sessionBus();
    bus.connect(kService, kPath, kInterface, QStringLiteral("layoutChanged"), this, SLOT(onLayoutChanged(uint)));
    bus.connect(kService, kPath, kInterface, QStringLiteral("layoutListChanged"), this, SLOT(readLayouts()));
    readLayouts();
}

int KeyboardLayout::layout() const
{
    return m_layout;
}

void KeyboardLayout::setLayout(int layout)
{
    QDBusMessage message = call(QStringLiteral("setLayout"));
    message << uint(layout);
    QDBusConnection::sessionBus().asyncCall(message);
}

QVariantList KeyboardLayout::layoutsList() const
{
    return m_layouts;
}

void KeyboardLayout::switchToNextLayout()
{
    QDBusConnection::sessionBus().asyncCall(call(QStringLiteral("switchToNextLayout")));
}

void KeyboardLayout::switchToPreviousLayout()
{
    QDBusConnection::sessionBus().asyncCall(call(QStringLiteral("switchToPreviousLayout")));
}

void KeyboardLayout::onLayoutChanged(uint index)
{
    if (int(index) != m_layout) {
        m_layout = int(index);
        Q_EMIT layoutChanged();
    }
}

void KeyboardLayout::readLayouts()
{
    auto *watcher = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(call(QStringLiteral("getLayoutsList"))), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *watcher) {
        watcher->deleteLater();
        QDBusPendingReply<QList<LayoutNames>> reply = *watcher;
        if (reply.isError())
            return;
        QVariantList layouts;
        for (const LayoutNames &names : reply.value()) {
            layouts.append(QVariantMap{
                {QStringLiteral("shortName"), names.shortName},
                {QStringLiteral("displayName"), names.displayName},
                {QStringLiteral("longName"), names.longName},
            });
        }
        m_layouts = layouts;
        Q_EMIT layoutsListChanged();
        readLayout();
    });
}

void KeyboardLayout::readLayout()
{
    auto *watcher = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(call(QStringLiteral("getLayout"))), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *watcher) {
        watcher->deleteLater();
        QDBusPendingReply<uint> reply = *watcher;
        if (!reply.isError())
            onLayoutChanged(reply.value());
    });
}
