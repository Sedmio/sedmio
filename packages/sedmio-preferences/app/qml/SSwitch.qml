import QtQuick

// Переключатель вкл/выкл.
Rectangle {
    id: root
    property bool checked: false
    signal toggled()

    implicitWidth: 40
    implicitHeight: 22
    radius: height / 2
    color: checked ? Theme.green : Theme.lineStrong
    Behavior on color { ColorAnimation { duration: Theme.animFast } }

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        x: root.checked ? parent.width - width - 3 : 3
        width: 16
        height: 16
        radius: 8
        color: Theme.surface
        Behavior on x { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled()
    }
}
