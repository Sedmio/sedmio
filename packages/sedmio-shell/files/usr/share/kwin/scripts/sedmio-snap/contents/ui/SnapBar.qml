import QtQuick
import Sedmio.Style

// Полоска схем у верхнего края (main.qml): пока курсор далеко — короткий
// язычок, подвёл — карточка со схемами. Часть схемы под курсором зелёная.
// Размеры и попадание курсора считает main.qml — тут только рисуем.
Item {
    id: view
    required property QtObject snap
    readonly property bool open: snap.barOpen

    Rectangle {
        id: card
        anchors.horizontalCenter: parent.horizontalCenter
        width: view.open ? view.width : 120
        height: view.open ? view.height : 10
        radius: view.open ? 16 : 5
        color: Theme.surface
        border.width: 1
        border.color: Theme.lineStrong
        clip: true
        Behavior on width { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
        Behavior on height { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
        Behavior on radius { NumberAnimation { duration: Theme.animFast } }

        Row {
            x: view.snap.barPad
            y: view.snap.barPad
            spacing: view.snap.barGap
            opacity: view.open ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.animFast } }

            Repeater {
                model: view.snap.dragLayouts

                Item {
                    id: thumb
                    required property var modelData
                    required property int index
                    width: view.snap.thumbWidth
                    height: view.snap.thumbHeight

                    Repeater {
                        model: thumb.modelData

                        Rectangle {
                            required property var modelData
                            required property int index
                            readonly property bool hovered: view.snap.hoverLayout === thumb.index
                                && view.snap.hoverZone === index
                            x: Math.round(modelData[0] * thumb.width) + 1
                            y: Math.round(modelData[1] * thumb.height) + 1
                            width: Math.round((modelData[0] + modelData[2]) * thumb.width) - x - 1
                            height: Math.round((modelData[1] + modelData[3]) * thumb.height) - y - 1
                            radius: 5
                            color: hovered ? Theme.green : Theme.paperDeep
                            border.width: 1
                            border.color: hovered ? Theme.green : Theme.line
                            Behavior on color { ColorAnimation { duration: Theme.animFast } }
                        }
                    }
                }
            }
        }
    }
}
