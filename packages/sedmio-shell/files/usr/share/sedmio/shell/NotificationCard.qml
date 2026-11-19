import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Notifications
import Quickshell.Widgets
import Sedmio.Style

// Карточка уведомления: значок программы, заголовок, текст, кнопки действий.
// Клик — действие по умолчанию. Всплывающая сама прячется по таймеру, если
// уведомление не срочное и мышь не над ней; крестик её только прячет —
// уведомление остаётся в истории. В истории (inHistory) крестик закрывает
// уведомление совсем.
Rectangle {
    id: card
    required property var notification
    property bool inHistory: false

    // Закрытое уведомление удаляется раньше карточки: пока она уходит,
    // notification уже null — поля читаем через ?. со значением по умолчанию.
    readonly property var info: ({
        id: notification?.id ?? -1,
        urgency: notification?.urgency ?? NotificationUrgency.Normal,
        actions: notification?.actions ?? [],
        desktopEntry: notification?.desktopEntry ?? "",
        appName: notification?.appName ?? "",
        appIcon: notification?.appIcon ?? "",
        image: notification?.image ?? "",
        summary: notification?.summary ?? "",
        body: notification?.body ?? "",
        expireTimeout: notification?.expireTimeout ?? 0
    })

    // Нажали на уведомление или его кнопку: программа сейчас откроется.
    signal activated()

    readonly property bool critical: info.urgency === NotificationUrgency.Critical
    readonly property var defaultAction: info.actions.find(a => a.identifier === "default") ?? null
    readonly property var buttons: info.actions.filter(a => a.identifier !== "default" && a.text !== "")

    readonly property var entry: DesktopEntries.applications.values.length >= 0
        ? (info.desktopEntry !== "" ? DesktopEntries.byId(info.desktopEntry)
           : DesktopEntries.heuristicLookup(info.appName)) : null

    // `notify-send -i имя` присылает значок из темы как картинку
    // (image://icon/имя). Это значок программы, а не миниатюра.
    readonly property string imageIconName: info.image.startsWith("image://icon/")
        ? info.image.substring(13).split("?")[0] : ""
    readonly property bool hasThumbnail: info.image !== "" && imageIconName === ""

    // Первый значок, который есть в теме или файлом.
    readonly property string appIconSource: {
        for (const name of [info.appIcon, imageIconName, entry ? entry.icon : ""]) {
            if (!name) continue;
            if (name.startsWith("/") || name.startsWith("file:")) return name;
            const path = Icons.path(name, true);
            if (path) return path;
        }
        return Icons.path("dialog-information");
    }

    implicitHeight: content.implicitHeight + 28
    radius: Theme.radius + 3
    color: Theme.surface
    border.width: critical ? 1 : 0
    border.color: Theme.terracotta

    // Спрятать всплывающую; мимолётное (громкость, «скопировано») при этом
    // и закрыть — в историю оно не идёт.
    function hidePopup() {
        if (!notification) return;
        if (notification.transient) notification.expire();
        else NotificationState.remove(notification);
    }

    Timer {
        // -1 — на усмотрение сервера: 6 секунд; 0 — не прятать.
        interval: card.info.expireTimeout > 0 ? card.info.expireTimeout : 6000
        running: !card.inHistory && !card.critical && card.info.expireTimeout !== 0 && !hover.containsMouse
        onTriggered: card.hidePopup()
    }

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        onClicked: {
            if (!card.notification) return;
            if (card.defaultAction) card.defaultAction.invoke();
            card.notification.dismiss();
            card.activated();
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
                text: (card.info.appName || (card.entry ? card.entry.name : ""))
                    + (card.inHistory ? " · " + NotificationState.ago(card.info) : "")
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
                    onClicked: card.inHistory ? card.notification?.dismiss() : card.hidePopup()
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
                    text: card.info.summary
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    size: 15
                    weight: 600
                }
                SText {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: card.info.body
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
                source: card.hasThumbnail ? card.info.image : ""
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
                            if (!card.notification) return;
                            parent.modelData.invoke();
                            card.notification.dismiss();
                            card.activated();
                        }
                    }
                }
            }
        }
    }
}
