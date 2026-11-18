import QtQuick

// Круглая кнопка со значком; подпись появляется под ней при наведении.
Item {
    id: root
    property string icon
    property string label
    signal clicked()

    implicitWidth: 44
    implicitHeight: 44

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: area.pressed ? Theme.paperDeep : area.containsMouse ? Theme.surface : Qt.rgba(1, 1, 1, 0.35)
        border.width: 1
        border.color: area.containsMouse ? Theme.lineStrong : Theme.line
        Behavior on color { ColorAnimation { duration: Theme.animFast } }

        Image {
            anchors.centerIn: parent
            width: 20
            height: 20
            sourceSize: Qt.size(40, 40)
            source: root.icon ? Theme.icon(root.icon) : ""
        }
    }

    SText {
        anchors { horizontalCenter: parent.horizontalCenter; top: parent.bottom; topMargin: 6 }
        text: root.label
        size: 12
        color: Theme.inkSoft
        opacity: area.containsMouse ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
