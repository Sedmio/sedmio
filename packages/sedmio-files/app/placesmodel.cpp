#include "placesmodel.h"

#include <KFilePlacesModel>
#include <KFormat>
#include <Solid/Device>
#include <Solid/StorageVolume>

PlacesModel::PlacesModel(QObject *parent)
    : QSortFilterProxyModel(parent)
    , m_places(new KFilePlacesModel(this))
{
    setSourceModel(m_places);

    connect(m_places, &KFilePlacesModel::setupDone, this, [this](const QModelIndex &index, bool success) {
        Q_EMIT setupDone(m_places->url(index), success);
    });
    connect(m_places, &KFilePlacesModel::errorMessage, this, &PlacesModel::errorMessage);
}

QHash<int, QByteArray> PlacesModel::roleNames() const
{
    return {
        {NameRole, "name"},
        {UrlRole, "url"},
        {IconRole, "iconName"},
        {SectionRole, "section"},
        {IsDeviceRole, "isDevice"},
        {SetupNeededRole, "setupNeeded"},
        {EjectableRole, "ejectable"},
    };
}

QVariant PlacesModel::data(const QModelIndex &index, int role) const
{
    const QModelIndex source = mapToSource(index);
    switch (role) {
    case NameRole: {
        const QString text = m_places->text(source);
        if (!text.isEmpty() || !m_places->isDevice(source))
            return text;
        // Раздел без метки: «Диск 512 ГБ».
        const Solid::Device device = m_places->deviceForIndex(source);
        if (const auto *volume = device.as<Solid::StorageVolume>(); volume && volume->size() > 0)
            return QStringLiteral("Диск %1").arg(KFormat().formatByteSize(volume->size(), 0, KFormat::MetricBinaryDialect));
        return QStringLiteral("Диск");
    }
    case UrlRole:
        return m_places->url(source);
    case IconRole:
        return source.data(KFilePlacesModel::IconNameRole);
    case SectionRole:
        switch (m_places->groupType(source)) {
        case KFilePlacesModel::PlacesType:
            return QStringLiteral("places");
        case KFilePlacesModel::RemoteType:
            return QStringLiteral("remote");
        case KFilePlacesModel::DevicesType:
            return QStringLiteral("devices");
        case KFilePlacesModel::RemovableDevicesType:
            return QStringLiteral("removable");
        default:
            return QStringLiteral("other");
        }
    case IsDeviceRole:
        return m_places->isDevice(source);
    case SetupNeededRole:
        return m_places->setupNeeded(source);
    case EjectableRole:
        return source.data(KFilePlacesModel::EjectAllowedRole).toBool()
            || source.data(KFilePlacesModel::TeardownAllowedRole).toBool();
    }
    return QSortFilterProxyModel::data(index, role);
}

bool PlacesModel::filterAcceptsRow(int sourceRow, const QModelIndex &sourceParent) const
{
    const QModelIndex index = m_places->index(sourceRow, 0, sourceParent);
    if (m_places->isHidden(index))
        return false;

    switch (m_places->groupType(index)) {
    case KFilePlacesModel::PlacesType:
    case KFilePlacesModel::RemoteType:
    case KFilePlacesModel::DevicesType:
    case KFilePlacesModel::RemovableDevicesType:
        break;
    default:
        return false; // недавние, поиск, метки
    }

    // Служебные разделы (EFI, загрузчик) — не для пользователя.
    const QString path = m_places->url(index).toLocalFile();
    if (path.startsWith(QLatin1String("/boot")) || path.startsWith(QLatin1String("/efi")))
        return false;
    return true;
}

void PlacesModel::setup(int row)
{
    m_places->requestSetup(mapToSource(index(row, 0)));
}

void PlacesModel::eject(int row)
{
    const QModelIndex source = mapToSource(index(row, 0));
    if (source.data(KFilePlacesModel::EjectAllowedRole).toBool())
        m_places->requestEject(source);
    else
        m_places->requestTeardown(source);
}

int PlacesModel::rowFor(const QUrl &url) const
{
    const QModelIndex closest = m_places->closestItem(url);
    if (!closest.isValid())
        return -1;
    return mapFromSource(closest).row();
}
