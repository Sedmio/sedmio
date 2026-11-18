pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Notifications

// Уведомления: сервер org.freedesktop.Notifications (раньше его держал
// plasmashell) и всплывающие карточки. История — позже, в панели управления.
Singleton {
    id: root

    // Всплывающие сейчас, новые сверху.
    property var popups: []
    readonly property int maxPopups: 4

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
