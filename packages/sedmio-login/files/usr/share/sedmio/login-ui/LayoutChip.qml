import QtQuick
import org.kde.plasma.workspace.keyboardlayout as Keyboard
import Sedmio.Style

// Текущая раскладка (её держит KWin); клик — следующая.
Item {
    id: root
    implicitWidth: 44
    implicitHeight: 44
    visible: layouts.layoutsList.length > 1

    Keyboard.KeyboardLayout { id: layouts }

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: area.containsMouse ? Theme.surface : Qt.rgba(1, 1, 1, 0.35)
        border.width: 1
        border.color: area.containsMouse ? Theme.lineStrong : Theme.line
        Behavior on color { ColorAnimation { duration: Theme.animFast } }

        SText {
            anchors.centerIn: parent
            text: (layouts.layoutsList[layouts.layout]?.shortName ?? "").toUpperCase()
            size: 13
            weight: 600
            color: Theme.inkSoft
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: layouts.switchToNextLayout()
    }
}
