import QtQuick
import org.kde.kwin as KWin
import org.kde.kirigami as Kirigami
import Sedmio.Style

// Подбор окна на свободное место (main.qml): миниатюры окон сеткой.
// Щелчок или Enter — это окно, Esc или щелчок по пустому — не надо.
// Стрелки — выбор, как в Windows.
Item {
    id: view
    property var windows: []
    signal picked(var window)
    signal cancelled()

    function reset() {
        grid.currentIndex = 0;
        grid.positionViewAtBeginning();
        grid.forceActiveFocus();
        appear.restart();
    }

    readonly property int margin: 24
    readonly property real avail: Math.max(1, width - 2 * margin)
    readonly property int columns: Math.max(1, Math.min(windows.length, Math.floor(avail / 200)))
    readonly property int cellWidth: Math.min(280, Math.floor(avail / columns))
    readonly property int thumbHeight: Math.round((cellWidth - 24) * 0.6)

    Rectangle {
        id: backdrop
        anchors { fill: parent; margins: 6 }
        radius: Theme.frameRadius
        color: Qt.alpha(Theme.paper, 0.93)
        border.width: 1
        border.color: Theme.line

        MouseArea {
            anchors.fill: parent
            onClicked: view.cancelled()
        }
    }

    GridView {
        id: grid
        anchors.centerIn: parent
        width: view.columns * cellWidth
        height: Math.min(Math.ceil(count / view.columns) * cellHeight, view.height - 2 * view.margin)
        cellWidth: view.cellWidth
        cellHeight: view.thumbHeight + 56
        model: view.windows
        focus: true
        keyNavigationWraps: true
        highlightMoveDuration: 0
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height
        clip: true

        Keys.onEscapePressed: view.cancelled()
        Keys.onReturnPressed: if (currentIndex >= 0) view.picked(view.windows[currentIndex])
        Keys.onEnterPressed: if (currentIndex >= 0) view.picked(view.windows[currentIndex])

        opacity: 0
        scale: 0.96
        ParallelAnimation {
            id: appear
            NumberAnimation { target: grid; property: "opacity"; from: 0; to: 1; duration: Theme.animNormal; easing.type: Easing.OutCubic }
            NumberAnimation { target: grid; property: "scale"; from: 0.96; to: 1; duration: Theme.animNormal; easing.type: Easing.OutCubic }
        }

        delegate: Item {
            id: cell
            required property var modelData
            required property int index
            readonly property bool current: GridView.isCurrentItem
            width: grid.cellWidth
            height: grid.cellHeight

            Rectangle {
                anchors { fill: parent; margins: 4 }
                radius: 12
                color: cell.current ? Theme.greenWash : Qt.alpha(Theme.paperDeep, 0)
                border.width: cell.current ? 1 : 0
                border.color: Theme.green
                Behavior on color { ColorAnimation { duration: Theme.animFast } }
            }

            KWin.WindowThumbnail {
                x: 12
                y: 12
                width: cell.width - 24
                height: view.thumbHeight
                wId: cell.modelData.internalId
            }

            Row {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 12; bottomMargin: 14 }
                spacing: 8

                Kirigami.Icon {
                    id: icon
                    anchors.verticalCenter: parent.verticalCenter
                    width: 20
                    height: 20
                    source: cell.modelData.icon
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - icon.width - parent.spacing
                    text: cell.modelData.caption
                    elide: Text.ElideRight
                    color: Theme.ink
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSmall
                    font.weight: cell.current ? Font.DemiBold : Font.Normal
                }
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onEntered: grid.currentIndex = cell.index
                onClicked: view.picked(cell.modelData)
            }
        }
    }
}
