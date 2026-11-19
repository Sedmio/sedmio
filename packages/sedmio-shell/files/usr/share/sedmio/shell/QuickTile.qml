import QtQuick
import QtQuick.Layouts
import Sedmio.Style

// Плитка панели управления: значок, название, состояние. Клик по плитке —
// включить/выключить, стрелка справа — подробнее (список сетей, устройств).
Rectangle {
    id: root
    property string icon
    property string title
    property string subtitle
    property bool active: false
    property bool hasDetails: false

    signal toggled()
    signal details()

    implicitHeight: 60
    radius: 16
    color: active ? (main.containsMouse ? Qt.lighter(Theme.green, 1.12) : Theme.green)
                  : (main.containsMouse ? Theme.paperDeep : Theme.surface)
    border.width: active ? 0 : 1
    border.color: Theme.line
    Behavior on color { ColorAnimation { duration: Theme.animFast } }

    MouseArea {
        id: main
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom; right: root.hasDetails ? more.left : parent.right }
        hoverEnabled: true
        onClicked: root.toggled()
    }

    RowLayout {
        anchors { left: parent.left; leftMargin: 14; right: root.hasDetails ? more.left : parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
        spacing: 12

        SIcon {
            name: root.icon
            light: root.active
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1
            SText {
                Layout.fillWidth: true
                text: root.title
                elide: Text.ElideRight
                size: Theme.fontBody
                weight: 600
                color: root.active ? Theme.textOnGreen : Theme.ink
            }
            SText {
                Layout.fillWidth: true
                visible: text !== ""
                text: root.subtitle
                elide: Text.ElideRight
                size: Theme.fontSmall
                color: root.active ? Qt.rgba(1, 1, 1, 0.78) : Theme.inkMuted
            }
        }
    }

    // Стрелка «подробнее»
    Item {
        id: more
        visible: root.hasDetails
        anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
        width: root.hasDetails ? 40 : 0

        Rectangle {
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            width: 1
            height: 26
            color: root.active ? Qt.rgba(1, 1, 1, 0.25) : Theme.line
        }
        Rectangle {
            anchors { fill: parent; margins: 6; leftMargin: 4 }
            radius: 11
            color: moreArea.containsMouse ? (root.active ? Qt.rgba(1, 1, 1, 0.14) : Theme.paperDeep) : Qt.alpha(root.active ? "white" : Theme.paperDeep, 0)
        }
        SIcon {
            anchors.centerIn: parent
            implicitSize: 16
            name: "go-next"
            light: root.active
        }
        MouseArea {
            id: moreArea
            anchors.fill: parent
            hoverEnabled: true
            onClicked: root.details()
        }
    }
}
