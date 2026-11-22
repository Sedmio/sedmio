import QtQuick
import Sedmio.Style

// Строка пакета AUR: поиск, установленные, обновления.
Rectangle {
    id: row
    property string name
    property string version
    property string summary
    property string badge
    property color badgeColor: Theme.green
    property string side
    property int inset: 6
    signal clicked()

    x: inset
    width: parent ? parent.width - 2 * inset : 0
    height: summary !== "" ? 64 : 48
    radius: Theme.radius
    color: area.containsMouse ? Theme.paperDeep : Theme.surface
    border.width: 1
    border.color: Theme.line

    Column {
        anchors { left: parent.left; leftMargin: 16; right: sideText.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
        spacing: 3
        Row {
            spacing: 8
            SText {
                text: row.name
                weight: 600
            }
            SText {
                anchors.verticalCenter: parent.verticalCenter
                text: row.version
                size: 12
                color: Theme.inkMuted
            }
            SText {
                visible: row.badge !== ""
                anchors.verticalCenter: parent.verticalCenter
                text: row.badge
                size: 12
                weight: 600
                color: row.badgeColor
            }
        }
        SText {
            visible: row.summary !== ""
            width: parent.width
            elide: Text.ElideRight
            size: 13
            color: Theme.inkSoft
            text: row.summary
        }
    }
    SText {
        id: sideText
        anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
        size: 12
        color: Theme.inkMuted
        text: row.side
    }
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: row.clicked()
    }
}
