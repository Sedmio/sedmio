import QtQuick
import QtQuick.Controls
import Sedmio.Store
import Sedmio.Style

// Добавленная AppImage: открыть, обновить с GitHub, удалить.
Item {
    id: root
    property string appId
    property bool confirmRemove: false
    property bool editSource: false

    readonly property var app: AppImages.list.find(a => a.id === root.appId) || ({})
    readonly property bool exists: app.id !== undefined
    readonly property var job: AppImages.work[appId] || ({})
    readonly property bool working: job.text !== undefined && (job.error || "") === "" && job.done !== true
    signal closed()

    function size(bytes) {
        const mb = (bytes || 0) / 1048576;
        return mb < 10 ? mb.toFixed(1).replace(".", ",") + " МБ" : Math.round(mb) + " МБ";
    }

    Flickable {
        anchors.fill: parent
        contentHeight: column.height + 48
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
            id: column
            x: Math.max(32, (root.width - width) / 2)
            width: Math.min(root.width - 64, 900)
            topPadding: 24
            spacing: 20

            Row {
                spacing: 20
                AppIcon {
                    size: 72
                    source: root.app.icon || ""
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4
                    SText {
                        text: root.exists ? root.app.name : "Программы больше нет"
                        size: 28
                        weight: 680
                    }
                    SText {
                        visible: text !== ""
                        text: root.app.comment || ""
                        size: 15
                        color: Theme.inkSoft
                        width: column.width - 92
                        wrapMode: Text.Wrap
                    }
                }
            }

            Rectangle {
                visible: root.exists
                width: parent.width
                height: actions.implicitHeight + 32
                radius: Theme.radius
                color: Theme.surface
                border.width: 2
                border.color: Theme.green

                Column {
                    id: actions
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
                    spacing: 10
                    SText {
                        width: parent.width
                        wrapMode: Text.Wrap
                        size: 13
                        color: Theme.inkSoft
                        text: (root.app.version ? "Версия " + root.app.version : "Версия неизвестна")
                            + (root.app.update ? ", на GitHub вышла " + root.app.update : "")
                    }
                    // Скачивается.
                    Column {
                        visible: root.working
                        width: parent.width
                        spacing: 8
                        SText {
                            width: parent.width
                            elide: Text.ElideRight
                            size: 13
                            color: Theme.inkSoft
                            text: root.job.text || ""
                        }
                        Rectangle {
                            width: parent.width
                            height: 6
                            radius: 3
                            color: Theme.paperDeep
                            Rectangle {
                                height: parent.height
                                radius: 3
                                color: Theme.green
                                width: parent.width * Math.max(0.03, root.job.progress >= 0 ? root.job.progress : 0.05)
                                Behavior on width { NumberAnimation { duration: 250 } }
                            }
                        }
                        SButton {
                            text: "Отменить"
                            onClicked: AppImages.cancel(root.appId)
                        }
                    }
                    Column {
                        visible: (root.job.error || "") !== ""
                        width: parent.width
                        spacing: 8
                        SText {
                            width: parent.width
                            wrapMode: Text.Wrap
                            size: 13
                            color: Theme.terracotta
                            text: root.job.error || ""
                        }
                        SButton {
                            text: "Понятно"
                            onClicked: AppImages.dismiss(root.appId)
                        }
                    }
                    Row {
                        visible: root.confirmRemove && !root.working
                        spacing: 8
                        SText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Удалить " + (root.app.name || "") + " вместе с файлом?"
                            weight: 600
                        }
                        SButton {
                            danger: true
                            text: "Удалить"
                            onClicked: {
                                root.confirmRemove = false;
                                AppImages.remove(root.appId);
                                root.closed();
                            }
                        }
                        SButton {
                            text: "Отмена"
                            onClicked: root.confirmRemove = false
                        }
                    }
                    Row {
                        visible: !root.working && (root.job.error || "") === "" && !root.confirmRemove
                        spacing: 8
                        SButton {
                            visible: (root.app.update || "") !== ""
                            primary: true
                            text: "Обновить до " + (root.app.update || "")
                            onClicked: AppImages.update(root.appId)
                        }
                        SButton {
                            primary: (root.app.update || "") === ""
                            text: "Открыть"
                            onClicked: AppImages.launch(root.appId)
                        }
                        SButton {
                            text: "Удалить"
                            onClicked: root.confirmRemove = true
                        }
                    }
                }
            }

            Card {
                visible: root.exists
                title: "Сведения"
                Info { label: "Файл"; value: root.app.file || "" }
                Info { label: "Размер"; value: root.app.size ? root.size(root.app.size) : "" }
                Info {
                    label: "Обновления"
                    value: root.app.github ? "с GitHub: " + root.app.github
                        + (root.app.selfUpdating ? " (так указано в самом файле)" : "")
                        + (AppImages.checking ? " — проверяю…" : root.app.checkError ? " — " + root.app.checkError : "")
                        : "не проверяются — неизвестно, откуда файл"
                }
                Item {
                    width: parent.width
                    height: 52
                    Row {
                        anchors { left: parent.left; leftMargin: 160; verticalCenter: parent.verticalCenter }
                        spacing: 8
                        SField {
                            id: repoField
                            visible: root.editSource
                            width: 280
                            placeholderText: "владелец/проект или ссылка"
                            text: root.app.github || ""
                            invalid: text !== "" && AppImages.parseRepo(text) === ""
                            onAccepted: saveButton.clicked()
                        }
                        SButton {
                            id: saveButton
                            visible: root.editSource
                            primary: true
                            text: "Сохранить"
                            onClicked: {
                                if (repoField.invalid) return;
                                AppImages.setGitHub(root.appId, repoField.text);
                                root.editSource = false;
                            }
                        }
                        SButton {
                            visible: !root.editSource
                            text: root.app.github ? "Другой проект…" : "Указать проект на GitHub…"
                            onClicked: root.editSource = true
                        }
                        SButton {
                            visible: !root.editSource && (root.app.github || "") !== ""
                            text: "Проверить сейчас"
                            onClicked: AppImages.checkUpdates(true)
                        }
                    }
                }
            }
            SText {
                visible: root.exists
                width: parent.width
                wrapMode: Text.Wrap
                size: 13
                color: Theme.inkMuted
                text: "У AppImage нет песочницы: программа может всё то же, что и вы."
            }
        }
    }

    component Info: Item {
        property string label
        property string value
        visible: value !== ""
        width: parent ? parent.width : 0
        height: Math.max(40, valueText.implicitHeight + 20)
        SText {
            anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
            text: parent.label
            color: Theme.inkSoft
        }
        SText {
            id: valueText
            anchors { left: parent.left; leftMargin: 160; right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
            text: parent.value
            wrapMode: Text.WrapAnywhere
        }
    }
}
