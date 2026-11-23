import QtQuick
import Quickshell
import Quickshell.Io
import qs

// Сервер уведомлений и команды центра.
Scope {
    // Обращение запускает сервер сразу, а не при первом показе карточек.
    Component.onCompleted: NotificationState.popups

    // Meta+N (usr/share/kglobalaccel/sedmio-notifications.desktop).
    IpcHandler {
        target: "notifications"
        function toggle(): void {
            if (ShellState.centerScreen !== "") ShellState.closeAll();
            else ShellState.openCenter(ShellState.focusedScreen());
        }
        function open(): void { ShellState.openCenter(ShellState.focusedScreen()); }
        function close(): void { ShellState.closeAll(); }
        function clear(): void { NotificationState.clearAll(); }
    }
}
