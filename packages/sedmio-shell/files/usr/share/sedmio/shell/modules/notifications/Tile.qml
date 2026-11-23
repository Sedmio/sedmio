import QtQuick
import qs

// Плитка «Не беспокоить» в Пуске (часть "tile").
QuickTile {
    icon: NotificationState.doNotDisturb ? "notifications-disabled" : "notifications"
    title: "Не беспокоить"
    subtitle: NotificationState.doNotDisturb ? "Только срочные" : "Выключено"
    active: NotificationState.doNotDisturb
    onToggled: NotificationState.setDoNotDisturb(!NotificationState.doNotDisturb)
}
