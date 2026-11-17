import QtQuick

// Светлая панель для списков. Без тени и градиентов: тонкая линия
// и подложка чуть светлее бумаги.
Rectangle {
    id: root

    default property alias content: column.data
    property int padding: 8
    property alias spacing: column.spacing

    implicitWidth: column.implicitWidth + 2 * padding
    implicitHeight: column.implicitHeight + 2 * padding
    radius: Theme.radiusLarge
    color: Theme.surface
    border.width: 1
    border.color: Theme.line

    Column {
        id: column
        x: root.padding
        y: root.padding
        width: root.width - 2 * root.padding
        spacing: 4
    }
}
