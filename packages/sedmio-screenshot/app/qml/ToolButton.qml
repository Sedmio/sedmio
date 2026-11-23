import QtQuick
import Sedmio.Style

// Кнопка-значок полосы инструментов. checked — выбранный инструмент.
Item {
    id: root
    property string icon
    property string hint
    property bool checked: false
    property bool enabled_: true
    signal clicked()

    implicitWidth: 36
    implicitHeight: 36
    opacity: enabled_ ? 1 : 0.4

    Rectangle {
        anchors.fill: parent
        radius: 10
        color: root.checked ? Theme.greenWash
             : area.containsMouse && root.enabled_ ? Theme.surface : Qt.alpha(Theme.surface, 0)
        border.width: root.checked ? 1 : 0
        border.color: Theme.green
        Behavior on color { ColorAnimation { duration: Theme.animFast } }
    }

    SIcon {
        anchors.centerIn: parent
        name: root.icon
        size: 18
        symbolic: true
        color: root.checked ? Theme.green : Theme.inkSoft
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        onClicked: if (root.enabled_) root.clicked()
    }

    // Подсказка снизу.
    Rectangle {
        visible: area.containsMouse && root.hint !== ""
        z: 10
        anchors { top: parent.bottom; topMargin: 6; horizontalCenter: parent.horizontalCenter }
        width: tip.implicitWidth + 16
        height: tip.implicitHeight + 8
        radius: 7
        color: Theme.ink
        SText {
            id: tip
            anchors.centerIn: parent
            text: root.hint
            size: 12
            color: Theme.paper
        }
    }
}
