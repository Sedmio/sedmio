import QtQuick
import QtQuick.Controls
import Sedmio.Store
import Sedmio.Style

// «Подробнее» у задания: что выводили pacman и makepkg, вживую.
Column {
    id: root
    property var job: ({})
    property bool open: false
    readonly property string text: root.job.id !== undefined && Jobs.logRevision >= 0 ? Jobs.log(root.job.id) : ""

    visible: text !== ""
    spacing: 6

    SText {
        text: root.open ? "Скрыть подробности" : "Подробнее"
        size: 13
        weight: 600
        color: Theme.green
        MouseArea {
            anchors.fill: parent
            anchors.margins: -4
            cursorShape: Qt.PointingHandCursor
            onClicked: root.open = !root.open
        }
    }

    Rectangle {
        visible: root.open
        width: root.width
        height: 240
        radius: Theme.radius
        color: Theme.paperDeep
        border.width: 1
        border.color: Theme.line

        ScrollView {
            id: scroll
            anchors { fill: parent; margins: 10 }
            clip: true
            TextArea {
                id: area
                readOnly: true
                selectByMouse: true
                wrapMode: TextEdit.WrapAnywhere
                text: root.text
                font.family: "monospace"
                font.pixelSize: 12
                color: Theme.ink
                selectionColor: Theme.greenSelect
                background: null
                padding: 0
                // Новое — внизу: держим низ на виду, если человек не листал вверх.
                onTextChanged: if (scroll.ScrollBar.vertical.position + scroll.ScrollBar.vertical.size > 0.97 || length < 2000)
                    Qt.callLater(() => scroll.ScrollBar.vertical.position = 1 - scroll.ScrollBar.vertical.size)
            }
        }
    }
}
