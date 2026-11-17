import QtQuick
import QtQuick.Templates as T

// Переключатель: текст и описание слева, «таблетка» справа.
// Бегунок переезжает пружиной и чуть сплющивается на ходу.
T.Switch {
    id: control

    property string description: ""

    implicitWidth: 420
    implicitHeight: Math.max(textColumn.implicitHeight, 30)
    hoverEnabled: true

    indicator: Rectangle {
        x: control.width - width
        anchors.verticalCenter: parent.verticalCenter
        width: 48
        height: 28
        radius: height / 2
        color: control.checked ? Theme.green : (control.hovered ? Theme.lineStrong : Theme.line)
        Behavior on color { ColorAnimation { duration: Theme.animNormal } }

        Rectangle {
            id: knob
            width: control.down ? 26 : 22
            height: 22
            radius: 11
            anchors.verticalCenter: parent.verticalCenter
            x: control.checked ? parent.width - width - 3 : 3
            color: Theme.surface
            Behavior on x { SpringAnimation { spring: 4; damping: 0.32 } }
            Behavior on width { NumberAnimation { duration: Theme.animFast } }
        }
    }

    contentItem: Column {
        id: textColumn
        spacing: 3

        Text {
            width: control.width - 64
            text: control.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontBody
            font.weight: Font.Medium
            color: Theme.ink
            wrapMode: Text.WordWrap
        }
        Text {
            visible: control.description !== ""
            width: control.width - 64
            text: control.description
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSmall
            lineHeight: 1.2
            color: Theme.inkMuted
            wrapMode: Text.WordWrap
        }
    }
}
