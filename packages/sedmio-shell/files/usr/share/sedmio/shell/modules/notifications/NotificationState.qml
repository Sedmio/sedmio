pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import qs

// Уведомления: сервер org.freedesktop.Notifications (раньше его держал
// plasmashell), всплывающие карточки, история и режим «Не беспокоить».
// Сервер в Quickshell один на процесс и имя на шине не отпускает, пока
// процесс жив, — поэтому выключение модуля перезапускает оболочку
// (restartOnDisable в module.json).
Singleton {
    id: root

    // Всплывающие сейчас, новые сверху.
    property var popups: []
    readonly property int maxPopups: 4

    // История — все пришедшие и не закрытые, новые сверху. Мимолётные
    // (transient: громкость, «скопировано») в историю не попадают.
    readonly property var history: server.trackedNotifications.values
        .filter(n => !n.transient)
        .reverse()

    // Когда пришло: id → Date (у самих уведомлений времени нет).
    property var arrived: ({})

    // Сколько пришло, пока центр уведомлений не открывали.
    property int unread: 0
    // Открыли центр — всё увидено: и всплывающие (срочные висят, пока их
    // не закроют) больше не нужны.
    function markRead() {
        unread = 0;
        popups = [];
    }

    // Закрыть все — как «Очистить всё» в центре уведомлений.
    function clearAll() {
        for (const n of history) n.dismiss();
    }

    // «Не беспокоить»: карточки не всплывают, кроме срочных; в историю
    // всё равно попадают. Хранится между сеансами.
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

            const times = Object.assign({}, root.arrived);
            times[notification.id] = new Date();
            root.arrived = times;

            if (!notification.transient && ShellState.centerScreen === "") root.unread++;

            if (!root.doNotDisturb || notification.urgency === NotificationUrgency.Critical)
                root.add(notification);
        }
    }

    function add(notification) {
        const list = popups.filter(n => n !== notification);
        list.unshift(notification);
        // Срочные не вытесняются обычными: иначе поток сообщений во время
        // игры убрал бы «батарея садится» с плашки поверх окна.
        const urgent = list.filter(n => n.urgency === NotificationUrgency.Critical);
        const normal = list.filter(n => n.urgency !== NotificationUrgency.Critical);
        popups = urgent.slice(0, maxPopups).concat(normal.slice(0, Math.max(0, maxPopups - urgent.length)));
        notification.closed.connect(() => root.remove(notification));
    }

    // Убрать карточку с экрана; уведомление остаётся в истории, пока его
    // не закроют. Мимолётное — закрыть совсем.
    function remove(notification) {
        popups = popups.filter(n => n !== notification);
    }

    // «5 мин назад», «вчера, 14:32».
    function ago(notification) {
        const when = arrived[notification.id];
        if (!when) return "";
        const minutes = Math.floor((clock.date - when) / 60000);
        if (minutes < 1) return "сейчас";
        if (minutes < 60) return minutes + " мин назад";
        const today = new Date(clock.date.getFullYear(), clock.date.getMonth(), clock.date.getDate());
        const time = Qt.formatTime(when, "hh:mm");
        if (when >= today) return time;
        if (when >= new Date(today - 86400000)) return "вчера, " + time;
        return when.toLocaleDateString(Qt.locale(), "d MMMM") + ", " + time;
    }

    SystemClock { id: clock; precision: SystemClock.Minutes }
}
