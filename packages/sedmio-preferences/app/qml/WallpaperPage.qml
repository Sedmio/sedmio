import QtCore
import QtQuick
import QtQuick.Dialogs
import Sedmio.Preferences

// «Обои»: миниатюры картинок из системы и «Изображений», первая — обои
// Sedmio. Щелчок — сразу на рабочий стол (оболочка следит за выбором).
Page {
    id: root
    title: "Обои"

    Wallpapers { id: wallpapers }

    // Первая плитка — свои обои Sedmio (путь пустой).
    readonly property var tiles: [{ path: "", name: "Обои Sedmio" }].concat(wallpapers.images)
    readonly property int columns: Math.max(2, Math.floor((contentWidth + 14) / 214))
    readonly property real tileWidth: (contentWidth - (columns - 1) * 14) / columns

    Row {
        spacing: 8
        SButton {
            text: "Выбрать файл…"
            primary: true
            onClicked: dialog.open()
        }
        SButton {
            text: "Обновить список"
            onClicked: wallpapers.rescan()
        }
    }

    SText {
        visible: wallpapers.error !== ""
        width: parent.width
        text: wallpapers.error
        color: Theme.terracotta
        wrapMode: Text.Wrap
    }

    Flow {
        width: parent.width
        spacing: 14

        Repeater {
            model: root.tiles
            delegate: Column {
                id: tile
                required property var modelData
                readonly property bool current: modelData.path === wallpapers.current
                width: root.tileWidth
                spacing: 6

                Rectangle {
                    width: parent.width
                    height: width * 10 / 16
                    radius: Theme.radius
                    color: Theme.paperDeep
                    border.width: tile.current ? 3 : 1
                    border.color: tile.current ? Theme.green : (tileArea.containsMouse ? Theme.lineStrong : Theme.line)

                    // Обои Sedmio — тот же градиент, что рисует оболочка.
                    Rectangle {
                        visible: tile.modelData.path === ""
                        anchors.fill: parent
                        anchors.margins: parent.border.width
                        radius: Theme.radius - 2
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: "#E8EDE3" }
                            GradientStop { position: 0.55; color: "#D6E1D0" }
                            GradientStop { position: 1.0; color: "#B9CCB3" }
                        }
                        SIcon {
                            anchors { right: parent.right; bottom: parent.bottom; margins: parent.height * 0.12 }
                            name: "sedmio"
                            size: parent.height * 0.4
                            opacity: 0.25
                        }
                    }

                    Image {
                        visible: tile.modelData.path !== ""
                        anchors.fill: parent
                        anchors.margins: parent.border.width
                        source: tile.modelData.url ?? ""
                        sourceSize: Qt.size(400, 250)
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: false
                        smooth: true
                    }

                    MouseArea {
                        id: tileArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: wallpapers.choose(tile.modelData.path)
                    }
                }

                SText {
                    width: parent.width
                    text: tile.modelData.name
                    size: Theme.fontSmall
                    weight: tile.current ? 600 : 400
                    color: tile.current ? Theme.ink : Theme.inkSoft
                    elide: Text.ElideMiddle
                }
            }
        }
    }

    FileDialog {
        id: dialog
        title: "Выбрать обои"
        currentFolder: StandardPaths.writableLocation(StandardPaths.PicturesLocation)
        nameFilters: ["Картинки (*.jpg *.jpeg *.png *.webp *.avif *.jxl)"]
        onAccepted: wallpapers.choose(selectedFile.toString())
    }
}
