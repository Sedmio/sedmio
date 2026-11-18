import QtQuick
import QtQuick.Effects
import org.kde.kwin as KWin
import org.kde.kirigami as Kirigami

// Вид переключателя: миниатюры окон сеткой на бумажной карточке, у каждой
// значок программы и заголовок. Выбранное окно — зелёная подложка.
// Цвета — из темы оболочки (/usr/share/sedmio/shell/Theme.qml).
Item {
    id: root
    required property QtObject switcher

    readonly property rect screen: switcher.screenGeometry
    readonly property real ratio: screen.width / Math.max(1, screen.height)
    readonly property int pad: 14
    readonly property int shadow: 24   // поле под тень вокруг карточки
    readonly property int thumbWidth: 220
    readonly property int thumbHeight: Math.round(thumbWidth / ratio)
    readonly property int cellWidth: thumbWidth + 20
    readonly property int cellHeight: thumbHeight + 20 + 34
    readonly property int columns: Math.max(1, Math.min(grid.count,
        Math.floor((screen.width * 0.9 - 2 * pad) / cellWidth)))
    readonly property int rows: Math.max(1, Math.ceil(grid.count / columns))

    implicitWidth: Math.max(columns * cellWidth, 260) + 2 * (pad + shadow)
    implicitHeight: Math.min(rows * cellHeight, screen.height * 0.7) + 2 * (pad + shadow)

    // Карточка с мягкой тенью — иначе сливается со светлыми окнами.
    Rectangle {
        id: card
        anchors { fill: parent; margins: root.shadow }
        radius: 18
        color: "#F8FAF5"
        border.width: 1
        border.color: "#D5DCCF"
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: "#1D2420"
            shadowOpacity: 0.22
            shadowBlur: 0.8
            shadowVerticalOffset: 4
        }
    }

    GridView {
        id: grid
        anchors { fill: card; margins: root.pad }
        model: root.switcher.model
        cellWidth: root.cellWidth
        cellHeight: root.cellHeight
        currentIndex: root.switcher.currentIndex
        onCurrentIndexChanged: root.switcher.currentIndex = currentIndex
        keyNavigationWraps: true
        highlightMoveDuration: 0
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        focus: true

        highlight: Rectangle {
            radius: 12
            color: "#DCE7DA"
            border.width: 1
            border.color: "#6E9C74"
        }

        delegate: MouseArea {
            id: cell
            width: grid.cellWidth
            height: grid.cellHeight
            hoverEnabled: true
            onClicked: root.switcher.model.activate(index)

            Rectangle {
                anchors.fill: parent
                radius: 12
                color: "#E3E8DE"
                visible: cell.containsMouse && !cell.GridView.isCurrentItem
            }

            Item {
                id: frame
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
                height: root.thumbHeight

                KWin.WindowThumbnail {
                    anchors.fill: parent
                    wId: model.windowId
                }

                Kirigami.Icon {
                    anchors { horizontalCenter: parent.horizontalCenter; verticalCenter: parent.bottom }
                    width: 40
                    height: 40
                    source: model.icon
                }
            }

            Text {
                anchors {
                    left: parent.left; right: parent.right; bottom: parent.bottom
                    leftMargin: 10; rightMargin: 10; bottomMargin: 8
                }
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                textFormat: Text.PlainText
                font.family: "Onest"
                font.pixelSize: 13
                font.weight: cell.GridView.isCurrentItem ? Font.DemiBold : Font.Normal
                color: cell.GridView.isCurrentItem ? "#1B251F" : "#4B5A50"
                text: model.caption
            }
        }
    }

    Text {
        anchors.centerIn: parent
        visible: grid.count === 0
        font.family: "Onest"
        font.pixelSize: 14
        color: "#7E8A81"
        text: "Нет открытых окон"
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Left) grid.moveCurrentIndexLeft();
        else if (event.key === Qt.Key_Right) grid.moveCurrentIndexRight();
        else if (event.key === Qt.Key_Up) grid.moveCurrentIndexUp();
        else if (event.key === Qt.Key_Down) grid.moveCurrentIndexDown();
    }
}
