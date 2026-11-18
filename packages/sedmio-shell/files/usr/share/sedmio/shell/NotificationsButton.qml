import QtQuick

// Колокольчик: клик — центр уведомлений, средняя кнопка — «Не беспокоить».
// Точка — пришли новые, пока центр не открывали.
BarButton {
    id: root
    required property string screenName
    readonly property int unread: NotificationState.unread
    readonly property int count: NotificationState.history.length

    active: ShellState.notificationsScreen === screenName
    hint: (NotificationState.doNotDisturb ? "Не беспокоить · " : "")
        + (count === 0 ? "Нет уведомлений" : "Уведомления: " + count)

    onClicked: event => {
        if (event.button === Qt.MiddleButton) {
            NotificationState.setDoNotDisturb(!NotificationState.doNotDisturb);
        } else {
            if (tooltip) tooltip.hide();
            ShellState.toggleNotifications(screenName);
        }
    }

    SIcon {
        anchors.centerIn: parent
        implicitSize: 20
        name: NotificationState.doNotDisturb ? "notifications-disabled" : "notifications"
    }

    Rectangle {
        visible: root.unread > 0
        x: parent.width / 2 + 3
        y: parent.height / 2 - 10
        width: 9
        height: 9
        radius: 4.5
        color: Theme.terracotta
        border.width: 2
        border.color: Theme.paper
    }
}
