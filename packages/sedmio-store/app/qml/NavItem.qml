import QtQuick
import Sedmio.Style

// Строка боковой панели: значок и название, текущая — подсвечена.
Rectangle {
    id: root
    property string icon
    property string text
    property bool current: false
    property int badge: 0
    signal clicked()

    width: parent ? parent.width : 0
    height: 36
    radius: 9
    color: current ? Theme.greenWash : area.containsMouse ? Theme.paper : Qt.alpha(Theme.paper, 0)
    Behavior on color { ColorAnimation { duration: Theme.animFast } }

    SIcon {
        id: glyph
        anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
        name: root.icon
        size: 22
    }
    SText {
        anchors { left: glyph.right; leftMargin: 10; right: count.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
        text: root.text
        weight: root.current ? 600 : 400
        elide: Text.ElideRight
    }
    Rectangle {
        id: count
        visible: root.badge > 0
        anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
        width: visible ? Math.max(22, badgeText.implicitWidth + 12) : 0
        height: 20
        radius: 10
        color: Theme.green
        SText {
            id: badgeText
            anchors.centerIn: parent
            text: root.badge
            size: 11
            weight: 650
            color: Theme.textOnGreen
        }
    }
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.clicked()
    }
}
