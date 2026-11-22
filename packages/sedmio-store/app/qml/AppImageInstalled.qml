import QtQuick
import Sedmio.Store
import Sedmio.Style

// Добавленные AppImage (под списком «Установленные» и в «Обновлениях»).
// onlyUpdates — только те, у которых на GitHub новый выпуск.
Column {
    id: root
    property bool onlyUpdates: false
    signal open(string id)
    signal add()

    readonly property var items: onlyUpdates ? AppImages.list.filter(a => a.update !== "") : AppImages.list
    visible: !onlyUpdates || items.length > 0
    Component.onCompleted: AppImages.checkUpdates(false)

    topPadding: onlyUpdates ? 0 : 8
    bottomPadding: onlyUpdates ? 0 : 32
    spacing: 10

    Item {
        width: parent.width
        height: Math.max(heading.implicitHeight, addButton.visible ? addButton.height : 0)
        SText {
            id: heading
            anchors.verticalCenter: parent.verticalCenter
            leftPadding: root.onlyUpdates ? 4 : 10
            text: "AppImage"
            size: 13
            weight: 600
            color: Theme.inkSoft
        }
        SButton {
            id: addButton
            anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
            visible: !root.onlyUpdates
            text: "Добавить AppImage…"
            onClicked: root.add()
        }
    }
    SText {
        visible: !root.onlyUpdates && root.items.length === 0
        x: 10
        width: parent.width - 20
        wrapMode: Text.Wrap
        size: 13
        color: Theme.inkMuted
        text: "Программы одним файлом. Перетащите файл .AppImage в это окно — он появится в меню и будет обновляться."
    }
    Repeater {
        model: root.items
        delegate: Rectangle {
            id: row
            required property var modelData
            readonly property var job: AppImages.work[modelData.id] || ({})
            x: root.onlyUpdates ? 0 : 6
            width: parent ? parent.width - 2 * x : 0
            height: 64
            radius: Theme.radius
            color: area.containsMouse ? Theme.paperDeep : Theme.surface
            border.width: 1
            border.color: Theme.line

            AppIcon {
                id: icon
                anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                size: 36
                source: row.modelData.icon
            }
            Column {
                anchors { left: icon.right; leftMargin: 12; right: side.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                spacing: 3
                Row {
                    spacing: 8
                    SText {
                        text: row.modelData.name
                        weight: 600
                    }
                    SText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: row.modelData.version || ""
                        size: 12
                        color: Theme.inkMuted
                    }
                    SText {
                        visible: row.modelData.update !== ""
                        anchors.verticalCenter: parent.verticalCenter
                        text: "есть " + row.modelData.update
                        size: 12
                        weight: 600
                        color: Theme.green
                    }
                }
                SText {
                    width: parent.width
                    elide: Text.ElideRight
                    size: 13
                    color: row.job.error ? Theme.terracotta : Theme.inkSoft
                    text: row.job.error || row.job.text || row.modelData.comment || ""
                }
            }
            SText {
                id: side
                anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                size: 12
                color: Theme.inkMuted
                text: row.modelData.update !== "" ? "Обновить ›" : "›"
            }
            MouseArea {
                id: area
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.open(row.modelData.id)
            }
        }
    }
}
