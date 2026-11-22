import QtQuick
import QtQuick.Controls
import Sedmio.Store
import Sedmio.Style

// Главная: подборка известных программ и разделы.
Item {
    id: root
    signal open(string id)

    readonly property int columns: Math.max(1, Math.floor((width - 48) / 300))
    readonly property real tileWidth: Math.floor((width - 48) / columns)
    readonly property var featured: Catalog.ready && Catalog.revision >= 0 ? Catalog.featured() : []

    Flickable {
        id: flick
        anchors.fill: parent
        contentHeight: column.height + 40
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
            id: column
            x: 24
            width: root.width - 48
            topPadding: 22
            spacing: 14

            // Каталог Flathub ещё не скачан (первый запуск) или не скачался.
            Rectangle {
                visible: Catalog.flathubStatus !== ""
                width: parent.width - 12
                x: 6
                height: 52
                radius: Theme.radius
                color: Catalog.flathubStatus === "loading" ? Theme.greenWash : Theme.surface
                border.width: Catalog.flathubStatus === "loading" ? 0 : 1
                border.color: Theme.line
                BusyIndicator {
                    id: flathubBusy
                    anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                    width: 32
                    height: 32
                    running: Catalog.flathubStatus === "loading"
                    visible: running
                }
                SText {
                    anchors { left: parent.left; leftMargin: flathubBusy.visible ? 52 : 16; right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                    elide: Text.ElideRight
                    color: Catalog.flathubStatus === "loading" ? Theme.ink : Theme.terracotta
                    text: Catalog.flathubStatus === "loading" ? "Скачиваю каталог Flathub — программы оттуда появятся через минуту"
                        : "Каталог Flathub недоступен: " + Catalog.flathubStatus
                }
            }

            SText {
                leftPadding: 8
                text: "Популярное"
                size: 24
                weight: 650
            }
            Flow {
                width: parent.width
                Repeater {
                    model: root.featured
                    delegate: Item {
                        required property var modelData
                        width: root.tileWidth
                        height: 124
                        AppTile {
                            anchors { fill: parent; margins: 6 }
                            app: parent.modelData
                            onClicked: root.open(app.id)
                        }
                    }
                }
            }
        }
    }
}
