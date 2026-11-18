import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Notifications
import Quickshell.Widgets

// Карточка уведомления: значок программы, заголовок, текст, кнопки действий.
// Клик — действие по умолчанию, крестик — закрыть. Сама прячется по
// таймеру, если уведомление не срочное и мышь не над ним.
Rectangle {
    id: card
    required property var notification

    readonly property bool critical: notification.urgency === NotificationUrgency.Critical
    readonly property var defaultAction: notification.actions.find(a => a.identifier === "default") ?? null
    readonly property var buttons: notification.actions.filter(a => a.identifier !== "default" && a.text !== "")

    readonly property var entry: DesktopEntries.applications.values.length >= 0
        ? (notification.desktopEntry !== "" ? DesktopEntries.byId(notification.desktopEntry)
           : DesktopEntries.heuristicLookup(notification.appName)) : null

    // `notify-send -i имя` присылает значок из темы как картинку
    // (image://icon/имя). Это значок программы, а не миниатюра.
    readonly property string imageIconName: notification.image.startsWith("image://icon/")
        ? notification.image.substring(13).split("?")[0] : ""
    readonly property bool hasThumbnail: notification.image !== "" && imageIconName === ""

    // Первый значок, который есть в теме или файлом.
    readonly property string appIconSource: {
        for (const name of [notification.appIcon, imageIconName, entry ? entry.icon : ""]) {
            if (!name) continue;
            if (name.startsWith("/") || name.startsWith("file:")) return name;
            const path = Quickshell.iconPath(name, true);
            if (path) return path;
        }
        return Quickshell.iconPath("dialog-information");
    }

    implicitHeight: content.implicitHeight + 28
    radius: Theme.radius + 3
    color: Theme.surface
    border.width: critical ? 1 : 0
    border.color: Theme.terracotta

    Timer {
        // -1 — на усмотрение сервера: 6 секунд; 0 — не прятать.
        interval: card.notification.expireTimeout > 0 ? card.notification.expireTimeout : 6000
        running: !card.critical && card.notification.expireTimeout !== 0 && !hover.containsMouse
        onTriggered: NotificationState.remove(card.notification)
    }

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        onClicked: {
            if (card.defaultAction) card.defaultAction.invoke();
            card.notification.dismiss();
        }
    }

    ColumnLayout {
        id: content
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            IconImage {
                Layout.alignment: Qt.AlignTop
                implicitSize: 20
                source: card.appIconSource
            }
            SText {
                Layout.fillWidth: true
                text: card.notification.appName || (card.entry ? card.entry.name : "")
                elide: Text.ElideRight
                size: Theme.fontSmall
                weight: 550
                color: Theme.inkMuted
            }
            // Закрыть
            Rectangle {
                Layout.alignment: Qt.AlignTop
                implicitWidth: 22
                implicitHeight: 22
                radius: 11
                color: closeArea.containsMouse ? Theme.paperDeep : "transparent"
                SText {
                    anchors.centerIn: parent
                    text: "✕"
                    size: 11
                    color: Theme.inkSoft
                }
                MouseArea {
                    id: closeArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: card.notification.dismiss()
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3

                SText {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: card.notification.summary
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    size: 15
                    weight: 600
                }
                SText {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: card.notification.body
                    textFormat: Text.StyledText
                    wrapMode: Text.Wrap
                    maximumLineCount: 4
                    elide: Text.ElideRight
                    size: Theme.fontBody
                    color: Theme.inkSoft
                    lineHeight: 1.1
                }
            }

            // Картинка уведомления (обложка, аватар, снимок экрана)
            Image {
                Layout.alignment: Qt.AlignTop
                Layout.preferredWidth: 52
                Layout.preferredHeight: 52
                visible: card.hasThumbnail && status === Image.Ready
                source: card.hasThumbnail ? card.notification.image : ""
                fillMode: Image.PreserveAspectCrop
                sourceSize: Qt.size(104, 104)
                asynchronous: true
            }
        }

        // Кнопки действий
        RowLayout {
            Layout.fillWidth: true
            visible: card.buttons.length > 0
            spacing: 6

            Repeater {
                model: card.buttons
                Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 32
                    radius: 10
                    color: actionArea.containsMouse ? Theme.greenWash : Theme.paperDeep
                    SText {
                        anchors.centerIn: parent
                        width: parent.width - 16
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: parent.modelData.text
                        size: 13
                        weight: 550
                    }
                    MouseArea {
                        id: actionArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            parent.modelData.invoke();
                            card.notification.dismiss();
                        }
                    }
                }
            }
        }
    }
}
