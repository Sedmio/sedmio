import QtQuick
import QtQuick.Templates as T

// Кнопка-«таблетка».
//  primary — залитая зелёным, со стрелкой, которая подаётся вперёд при наведении;
//  иначе — тихая, только текст и мягкая подложка при наведении.
T.Button {
    id: control

    property bool primary: false
    property bool arrow: primary

    implicitWidth: Math.max(primary ? 132 : 96, contentItem.implicitWidth + leftPadding + rightPadding)
    implicitHeight: Theme.controlHeight
    leftPadding: primary ? 26 : 18
    rightPadding: primary ? 22 : 18
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus

    // Лёгкое «нажатие» пружиной
    scale: down ? 0.96 : 1
    Behavior on scale { SpringAnimation { spring: 6; damping: 0.35 } }

    contentItem: Row {
        spacing: 10

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: control.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontBody
            font.weight: control.primary ? Font.DemiBold : Font.Medium
            color: control.primary ? Theme.textOnGreen
                 : control.hovered ? Theme.ink : Theme.inkSoft
        }

        Text {
            visible: control.arrow
            anchors.verticalCenter: parent.verticalCenter
            text: "→"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontLarge
            color: Theme.textOnGreen
            transform: Translate {
                x: control.hovered ? 4 : 0
                Behavior on x { SpringAnimation { spring: 5; damping: 0.3 } }
            }
        }
    }

    background: Rectangle {
        radius: height / 2
        color: {
            if (control.primary) {
                if (control.down) return Theme.greenPressed
                return control.hovered ? Theme.greenHover : Theme.green
            }
            return control.down ? Theme.line
                 : control.hovered ? Theme.paperDeep : "transparent"
        }
        border.width: control.visualFocus ? 2 : 0
        border.color: Theme.terracotta
        Behavior on color { ColorAnimation { duration: Theme.animFast } }
    }

    opacity: enabled ? 1 : 0.35
    Behavior on opacity { NumberAnimation { duration: Theme.animNormal } }
}
