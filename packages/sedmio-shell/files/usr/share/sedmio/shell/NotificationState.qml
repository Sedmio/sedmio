pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

// Уведомления: сервер org.freedesktop.Notifications (раньше его держал
// plasmashell), всплывающие карточки и режим «Не беспокоить».
Singleton {
    id: root

    // Всплывающие сейчас, новые сверху.
    property var popups: []
    readonly property int maxPopups: 4

    // Все, что пришли и ещё не закрыты, — для истории.
    readonly property var history: server.trackedNotifications

    // «Не беспокоить»: карточки не всплывают, кроме срочных.
    // Хранится между сеансами.
    property bool doNotDisturb: false

    readonly property string statePath:
        (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state")
        + "/sedmio/notifications.json"

    FileView {
        id: stateFile
        path: root.statePath
        printErrors: false
        onLoaded: {
            try {
                root.doNotDisturb = JSON.parse(text()).doNotDisturb === true;
            } catch (e) {}
        }
    }

    function setDoNotDisturb(enabled) {
        doNotDisturb = enabled;
        if (enabled) popups = popups.filter(n => n.urgency === NotificationUrgency.Critical);
        stateFile.setText(JSON.stringify({ doNotDisturb: enabled }, null, 2));
    }

    NotificationServer {
        id: server
        keepOnReload: false
        bodySupported: true
        bodyMarkupSupported: true
        bodyHyperlinksSupported: false
        imageSupported: true
        actionsSupported: true
        actionIconsSupported: false
        persistenceSupported: true

        onNotification: notification => {
            notification.tracked = true;
            if (!root.doNotDisturb || notification.urgency === NotificationUrgency.Critical)
                root.add(notification);
        }
    }

    function add(notification) {
        const list = popups.filter(n => n !== notification);
        list.unshift(notification);
        popups = list.slice(0, maxPopups);
        notification.closed.connect(() => root.remove(notification));
    }

    // Убрать карточку; само уведомление остаётся в истории, пока его не закроют.
    function remove(notification) {
        popups = popups.filter(n => n !== notification);
    }
}
