// sedmio-devices — уведомление, когда подключили флешку или вставили диск:
// «Открыть» (подключить и показать в «Файлах») и «Извлечь» (отключить,
// чтобы можно было вынуть). В Plasma это делал апплет «Подключённые
// устройства» на панели plasmashell, у нас панели Plasma нет.
//
// Запускает служба sedmio-devices.service в сеансе пользователя.
// Уведомления показывает оболочка (org.freedesktop.Notifications), «Файлы»
// открываются через org.freedesktop.FileManager1 — так же, как из других
// программ. Упала — systemd перезапустит; без неё флешки по-прежнему видны
// в «Файлах», просто без уведомления.

#include <KFormat>

#include <Solid/Device>
#include <Solid/DeviceNotifier>
#include <Solid/OpticalDisc>
#include <Solid/OpticalDrive>
#include <Solid/StorageAccess>
#include <Solid/StorageDrive>
#include <Solid/StorageVolume>

#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QHash>
#include <QLoggingCategory>
#include <QPointer>
#include <QUrl>

// Что происходит — в журнал сеанса (journalctl --user -u sedmio-devices).
Q_LOGGING_CATEGORY(logDevices, "sedmio.devices", QtInfoMsg)

namespace
{
const QString notifyService = QStringLiteral("org.freedesktop.Notifications");
const QString notifyPath = QStringLiteral("/org/freedesktop/Notifications");
const QString notifyInterface = QStringLiteral("org.freedesktop.Notifications");

// Диск, к которому относится раздел (у флешки без разделов — он сам).
Solid::StorageDrive *driveOf(Solid::Device device)
{
    while (device.isValid()) {
        if (auto *drive = device.as<Solid::StorageDrive>())
            return drive;
        device = device.parent();
    }
    return nullptr;
}

QDBusConnection bus()
{
    return QDBusConnection::sessionBus();
}
} // namespace

class Devices : public QObject
{
    Q_OBJECT

public:
    Devices()
    {
        auto *notifier = Solid::DeviceNotifier::instance();
        connect(notifier, &Solid::DeviceNotifier::deviceAdded, this, &Devices::onAdded);
        connect(notifier, &Solid::DeviceNotifier::deviceRemoved, this, &Devices::onRemoved);

        // От любого отправителя, а не от org.freedesktop.Notifications: мы
        // стартуем вместе с оболочкой, и пока она не заняла имя, QtDBus не
        // узнаёт в ней отправителя — сигналы терялись. Номера уведомлений
        // наши, чужие сигналы с ними не совпадут.
        const bool actions = bus().connect(QString(), notifyPath, notifyInterface, QStringLiteral("ActionInvoked"),
                                           this, SLOT(onActionInvoked(uint,QString)));
        const bool closed = bus().connect(QString(), notifyPath, notifyInterface, QStringLiteral("NotificationClosed"),
                                          this, SLOT(onClosed(uint,uint)));
        if (!actions || !closed)
            qCWarning(logDevices) << "Could not listen to notification signals";
    }

private Q_SLOTS:
    void onActionInvoked(uint id, const QString &action)
    {
        const QString udi = m_udiById.value(id);
        qCInfo(logDevices) << "action" << action << "on notification" << id << udi;
        if (udi.isEmpty())
            return;
        if (action == QLatin1String("default") || action == QLatin1String("open"))
            open(udi);
        else if (action == QLatin1String("eject"))
            eject(udi);
    }

    void onClosed(uint id, uint /*reason*/)
    {
        m_idByUdi.remove(m_udiById.take(id));
    }

private:
    // Подключили: раздел с файловой системой на съёмном диске.
    void onAdded(const QString &udi)
    {
        const Solid::Device device(udi);
        if (!device.is<Solid::StorageAccess>())
            return;
        const auto *volume = device.as<Solid::StorageVolume>();
        if (volume && (volume->isIgnored() || volume->usage() != Solid::StorageVolume::FileSystem))
            return;
        const auto *drive = driveOf(device);
        if (!drive || !(drive->isHotpluggable() || drive->isRemovable()))
            return;

        const bool optical = device.is<Solid::OpticalDisc>();
        const bool usb = drive->bus() == Solid::StorageDrive::Usb;
        const QString icon = optical ? QStringLiteral("media-optical")
            : usb                    ? QStringLiteral("drive-removable-media-usb")
                                     : QStringLiteral("drive-removable-media");

        QString name = volume ? volume->label() : QString();
        if (name.isEmpty())
            name = device.description();

        QString body = optical ? QStringLiteral("Диск вставлен")
            : usb && drive->driveType() == Solid::StorageDrive::HardDisk && !drive->isRemovable()
            ? QStringLiteral("Диск подключён")
            : QStringLiteral("Флешка подключена");
        if (volume && volume->size() > 0)
            body += QStringLiteral(" · ") + KFormat().formatByteSize(volume->size(), 0, KFormat::MetricBinaryDialect);

        notify(udi, icon, name, body,
               {QStringLiteral("default"), QString(),
                QStringLiteral("open"), QStringLiteral("Открыть"),
                QStringLiteral("eject"), QStringLiteral("Извлечь")},
               false);
    }

    // Вынули: уведомление о нём больше не нужно.
    void onRemoved(const QString &udi)
    {
        const uint id = m_idByUdi.take(udi);
        if (!id)
            return;
        m_udiById.remove(id);
        auto message = QDBusMessage::createMethodCall(notifyService, notifyPath, notifyInterface,
                                                      QStringLiteral("CloseNotification"));
        message << id;
        bus().call(message, QDBus::NoBlock);
    }

    void open(const QString &udi)
    {
        Solid::Device device(udi);
        auto *access = device.as<Solid::StorageAccess>();
        if (!access)
            return;
        if (access->isAccessible()) {
            showFolder(access->filePath());
            return;
        }
        QPointer<Solid::StorageAccess> guard(access);
        connect(access, &Solid::StorageAccess::setupDone, this,
                [this, guard, udi](Solid::ErrorType error, const QVariant &errorData, const QString &) {
                    if (guard)
                        disconnect(guard, &Solid::StorageAccess::setupDone, this, nullptr);
                    if (error == Solid::NoError && guard)
                        showFolder(guard->filePath());
                    else if (error != Solid::UserCanceled)
                        notifyError(udi, QStringLiteral("Не удалось открыть"), errorData.toString());
                });
        qCInfo(logDevices) << "mounting" << udi;
        if (!access->setup())
            qCWarning(logDevices) << "Could not start mounting" << udi;
    }

    void eject(const QString &udi)
    {
        Solid::Device device(udi);
        auto *access = device.as<Solid::StorageAccess>();
        if (!access)
            return;
        auto done = [this, udi](Solid::ErrorType error, const QVariant &errorData) {
            if (error == Solid::NoError) {
                Solid::Device device(udi);
                if (auto *drive = device.parent().as<Solid::OpticalDrive>())
                    drive->eject();
                notify(udi, QStringLiteral("drive-removable-media"), QStringLiteral("Можно извлечь"),
                       Solid::Device(udi).description(), {}, true);
            } else if (error != Solid::UserCanceled) {
                notifyError(udi, QStringLiteral("Не удалось извлечь"),
                            error == Solid::DeviceBusy
                                ? QStringLiteral("Файлы с него ещё открыты в какой-то программе.")
                                : errorData.toString());
            }
        };
        if (!access->isAccessible()) {
            done(Solid::NoError, {});
            return;
        }
        QPointer<Solid::StorageAccess> guard(access);
        connect(access, &Solid::StorageAccess::teardownDone, this,
                [this, guard, done](Solid::ErrorType error, const QVariant &errorData, const QString &) {
                    if (guard)
                        disconnect(guard, &Solid::StorageAccess::teardownDone, this, nullptr);
                    done(error, errorData);
                });
        qCInfo(logDevices) << "unmounting" << udi;
        if (!access->teardown())
            qCWarning(logDevices) << "Could not start unmounting" << udi;
    }

    void showFolder(const QString &path)
    {
        auto message = QDBusMessage::createMethodCall(QStringLiteral("org.freedesktop.FileManager1"),
                                                      QStringLiteral("/org/freedesktop/FileManager1"),
                                                      QStringLiteral("org.freedesktop.FileManager1"),
                                                      QStringLiteral("ShowFolders"));
        message << QStringList{QUrl::fromLocalFile(path).toString()} << QString();
        bus().call(message, QDBus::NoBlock);
    }

    void notifyError(const QString &udi, const QString &summary, const QString &body)
    {
        notify(udi, QStringLiteral("dialog-warning"), summary, body, {}, true);
    }

    // Новое уведомление об устройстве заменяет прежнее о нём же.
    void notify(const QString &udi, const QString &icon, const QString &summary, const QString &body,
                const QStringList &actions, bool transient)
    {
        auto message = QDBusMessage::createMethodCall(notifyService, notifyPath, notifyInterface,
                                                      QStringLiteral("Notify"));
        QVariantMap hints{{QStringLiteral("desktop-entry"), QStringLiteral("sedmio-files")}};
        if (transient)
            hints.insert(QStringLiteral("transient"), true);
        message << QStringLiteral("Устройства") << m_idByUdi.value(udi) << icon << summary << body
                << actions << hints << -1;

        auto *watcher = new QDBusPendingCallWatcher(bus().asyncCall(message), this);
        connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, udi, transient](QDBusPendingCallWatcher *call) {
            call->deleteLater();
            const QDBusPendingReply<uint> reply = *call;
            if (reply.isError()) {
                qCWarning(logDevices) << "Could not notify:" << reply.error().message();
                return;
            }
            const uint old = m_idByUdi.take(udi);
            m_udiById.remove(old);
            if (transient)
                return;
            m_idByUdi.insert(udi, reply.value());
            m_udiById.insert(reply.value(), udi);
        });
    }

    QHash<QString, uint> m_idByUdi;
    QHash<uint, QString> m_udiById;
};

int main(int argc, char *argv[])
{
    QCoreApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("sedmio-devices"));
    Devices devices;
    return app.exec();
}

#include "devices.moc"
