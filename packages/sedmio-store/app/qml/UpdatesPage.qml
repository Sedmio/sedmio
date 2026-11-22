import QtQuick
import QtQuick.Controls
import Sedmio.Store
import Sedmio.Style

// Обновления программ Flathub. Программы из репозиториев Arch обновляются
// вместе с системой — в «Параметры» → «Обновление» (частичные обновления
// в Arch ломают систему, поэтому по одной их не обновляем).
Item {
    id: root
    signal open(string id)
    signal reviewAur(var names)

    readonly property var job: Jobs.list.length >= 0 ? Jobs.forApp("@updates") : ({})
    readonly property bool updating: job.state === "running" || job.state === "waiting"
    Component.onCompleted: Catalog.checkUpdates()
    // Обновили — проверить снова.
    Connections {
        target: Jobs
        function onFinished(appId, name, action, ok) {
            if (action === "update") Catalog.checkUpdates();
        }
    }

    Flickable {
        anchors.fill: parent
        contentHeight: column.height + 40
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
            id: column
            x: 32
            width: Math.min(root.width - 64, 820)
            topPadding: 22
            spacing: 16

            SText {
                text: "Обновления"
                size: 24
                weight: 650
            }

            // Flathub.
            Card {
                title: "Программы с Flathub"
                Item {
                    width: parent.width
                    height: 64
                    SText {
                        anchors { left: parent.left; leftMargin: 16; right: updateAll.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                        wrapMode: Text.Wrap
                        color: Theme.inkSoft
                        text: Catalog.checkingUpdates ? "Проверяю…"
                            : root.updating ? (root.job.text || "Обновляю…")
                            : Catalog.updatesError !== "" ? Catalog.updatesError
                            : Catalog.updates.length === 0 ? "Всё обновлено"
                            : "Есть обновления: " + Catalog.updates.length
                    }
                    SButton {
                        id: updateAll
                        anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                        visible: !Catalog.checkingUpdates && !root.updating
                        primary: Catalog.updates.length > 0
                        text: Catalog.updates.length > 0 ? "Обновить всё" : "Проверить"
                        onClicked: Catalog.updates.length > 0 ? Jobs.updateFlatpaks([]) : Catalog.checkUpdates()
                    }
                }
                Repeater {
                    model: Catalog.updates
                    delegate: Item {
                        required property var modelData
                        width: parent.width
                        height: 60
                        Rectangle {
                            anchors { left: parent.left; right: parent.right; top: parent.top }
                            height: 1
                            color: Theme.line
                        }
                        AppIcon {
                            id: rowIcon
                            anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
                            source: parent.modelData.icon || ""
                            size: 36
                        }
                        SText {
                            anchors { left: rowIcon.right; leftMargin: 12; right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                            text: parent.modelData.name
                            weight: 600
                            elide: Text.ElideRight
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.open(parent.modelData.id)
                        }
                    }
                }
            }

            AurInstalled {
                width: parent.width
                topPadding: 0
                bottomPadding: 0
                onlyUpdates: true
                onOpen: name => root.open("aur:" + name)
                onReviewAll: names => root.reviewAur(names)
            }
            AppImageInstalled {
                width: parent.width
                onlyUpdates: true
                onOpen: id => root.open("appimage:" + id)
            }

            // Arch.
            Card {
                title: "Программы из репозиториев Arch"
                Item {
                    width: parent.width
                    height: archText.implicitHeight + 32
                    SText {
                        id: archText
                        anchors { left: parent.left; leftMargin: 16; right: openUpdates.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                        wrapMode: Text.Wrap
                        color: Theme.inkSoft
                        text: "Обновляются вместе с системой, все сразу: по одной в Arch нельзя — новая программа на старых библиотеках ломается."
                    }
                    SButton {
                        id: openUpdates
                        anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                        text: "Обновление системы"
                        onClicked: StoreHost.openSystemUpdates()
                    }
                }
            }
        }
    }
}
