import QtQuick
import io.calamares.ui 1.0
import io.calamares.core 1.0
import "components"

// Верхняя полоса (sidebar: qml,top): знак, название и прогресс шагов
// сегментами. Текущий сегмент — терракотовый и длиннее, пройденные —
// зелёные. Ширина сегментов меняется пружиной.
Rectangle {
    id: bar

    height: 64
    color: Theme.paper

    readonly property int current: ViewManager.currentStepIndex
    readonly property int total: ViewManager.rowCount()

    Row {
        anchors.left: parent.left
        anchors.leftMargin: Theme.sideMargin
        anchors.verticalCenter: parent.verticalCenter
        spacing: 10

        Logo {
            size: 26
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "sedmio"
            font.family: Theme.fontFamily
            font.pixelSize: 20
            font.weight: Font.DemiBold
            font.letterSpacing: -0.6
            color: Theme.ink
        }
    }

    Row {
        anchors.right: parent.right
        anchors.rightMargin: Theme.sideMargin
        anchors.verticalCenter: parent.verticalCenter
        spacing: 18

        Text {
            id: stepName
            anchors.verticalCenter: parent.verticalCenter
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSmall
            color: Theme.inkMuted
            text: (bar.current + 1) + " из " + bar.total
        }

        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 5

            Repeater {
                model: ViewManager

                delegate: Rectangle {
                    readonly property bool isCurrent: index === bar.current
                    readonly property bool isDone: index < bar.current

                    width: isCurrent ? 36 : 14
                    height: 6
                    radius: 3
                    color: isCurrent ? Theme.terracotta : isDone ? Theme.green : Theme.line
                    Behavior on width { SpringAnimation { spring: 3; damping: 0.3 } }
                    Behavior on color { ColorAnimation { duration: Theme.animNormal } }
                }
            }
        }
    }
}
