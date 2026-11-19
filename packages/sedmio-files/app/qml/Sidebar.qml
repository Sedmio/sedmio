import QtQuick
import QtQuick.Controls
import Sedmio.Files
import Sedmio.Style

// Места слева: свои папки и корзина, сеть, диски и флешки. Флешку
// перед открытием подключаем; у подключённой — кнопка «Извлечь».
Rectangle {
    id: root
    property url currentUrl
    signal openRequested(url url)
    // Средняя кнопка — открыть во вкладке.
    signal openInNewTabRequested(url url)
    // Бросили файлы на место: скопировать или перенести туда.
    signal dropped(var urls, url destination, var drop)

    color: Theme.paper

    readonly property var sectionNames: ({
        places: "",
        remote: "Сеть",
        devices: "Диски",
        removable: "Съёмные"
    })

    PlacesModel {
        id: places
        onSetupDone: (url, success) => {
            if (success) root.openRequested(url);
        }
    }

    ListView {
        id: list
        anchors.fill: parent
        anchors.margins: 10
        clip: true
        model: places
        spacing: 2
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        readonly property int currentRow: places.rowFor(root.currentUrl)

        section.property: "section"
        section.delegate: Item {
            required property string section
            width: list.width
            height: root.sectionNames[section] ? 34 : 0
            visible: height > 0
            SText {
                anchors { left: parent.left; leftMargin: 10; bottom: parent.bottom; bottomMargin: 6 }
                text: root.sectionNames[parent.section] ?? ""
                size: Theme.fontSmall
                weight: 600
                color: Theme.inkMuted
            }
        }

        delegate: Rectangle {
            id: row
            required property int index
            required property string name
            required property url url
            required property string iconName
            required property bool setupNeeded
            required property bool ejectable

            readonly property bool current: list.currentRow === index
            width: list.width
            height: 34
            radius: 9
            color: current ? Theme.greenWash
                 : drop.containsDrag ? Theme.greenSelect
                 : mouse.containsMouse ? Theme.paperDeep : Qt.alpha(Theme.paperDeep, 0)

            SIcon {
                id: icon
                anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                name: row.iconName
                size: 16
                opacity: row.setupNeeded ? 0.6 : 1
            }
            SText {
                anchors { left: icon.right; leftMargin: 10; right: eject.left; rightMargin: 4; verticalCenter: parent.verticalCenter }
                text: row.name
                elide: Text.ElideRight
                weight: row.current ? 600 : 450
                color: row.setupNeeded ? Theme.inkSoft : Theme.ink
            }

            MouseArea {
                id: mouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                onClicked: mouse => {
                    if (row.setupNeeded) places.setup(row.index);
                    else if (mouse.button === Qt.MiddleButton) root.openInNewTabRequested(row.url);
                    else root.openRequested(row.url);
                }
            }

            // Извлечь флешку
            Rectangle {
                id: eject
                anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
                width: visible ? 26 : 0
                height: 26
                radius: 8
                visible: row.ejectable && !row.setupNeeded
                color: ejectArea.containsMouse ? Theme.paper : Qt.alpha(Theme.paper, 0)
                SIcon {
                    anchors.centerIn: parent
                    name: "media-eject"
                    size: 16
                }
                MouseArea {
                    id: ejectArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: places.eject(row.index)
                }
            }

            DropArea {
                id: drop
                anchors.fill: parent
                enabled: !row.setupNeeded
                keys: ["text/uri-list"]
                onDropped: event => root.dropped(event.urls, row.url, event)
            }
        }
    }
}
