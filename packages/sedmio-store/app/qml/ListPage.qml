import QtQuick
import QtQuick.Controls
import Sedmio.Style

// Страница-список плиток: раздел, результаты поиска, установленное.
Item {
    id: root
    property string title
    property string subtitle
    property var apps: []
    property string emptyText: "Ничего нет"
    // Под плитками (поиск — блок AUR).
    property Component footer: null
    property bool emptyVisible: apps.length === 0 && footer === null
    signal open(string id)

    readonly property int columns: Math.max(1, Math.floor((width - 48) / 300))

    GridView {
        id: grid
        anchors { fill: parent; leftMargin: 24; rightMargin: 24 }
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        cellWidth: Math.floor(width / root.columns)
        cellHeight: 124
        model: root.apps
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        // Прокрутка к началу при смене списка (другой раздел, новый запрос).
        onModelChanged: positionViewAtBeginning()

        header: Column {
            width: grid.width
            topPadding: 22
            bottomPadding: 16
            leftPadding: 8
            spacing: 4
            SText {
                text: root.title
                size: 24
                weight: 650
            }
            SText {
                visible: text !== ""
                text: root.subtitle
                color: Theme.inkMuted
            }
        }

        footer: root.footer ? footerBox : null
        Component {
            id: footerBox
            Loader {
                width: grid.width
                sourceComponent: root.footer
            }
        }

        delegate: Item {
            required property var modelData
            width: grid.cellWidth
            height: grid.cellHeight
            AppTile {
                anchors { fill: parent; margins: 6 }
                app: parent.modelData
                onClicked: root.open(app.id)
            }
        }
    }

    SText {
        anchors.centerIn: parent
        visible: root.emptyVisible
        text: root.emptyText
        color: Theme.inkMuted
        size: 15
    }
}
