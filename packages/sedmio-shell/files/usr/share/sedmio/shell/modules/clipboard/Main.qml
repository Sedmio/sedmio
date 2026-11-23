import QtQuick
import Quickshell
import Quickshell.Io
import qs

// История буфера обмена: Meta+V (usr/share/kglobalaccel/sedmio-clipboard.desktop) —
//   quickshell ipc -p /usr/share/sedmio/shell call clipboard toggle
// Шторка сверху посередине — Panel.qml (ShellState.openPanel).
Scope {
    IpcHandler {
        target: "clipboard"
        // Открыта на любом экране — закрыть.
        function toggle(): void {
            if (ShellState.panelScreen !== "" && ShellState.panelModule === "clipboard") ShellState.closeAll();
            else ShellState.openPanel(ShellState.focusedScreen(), "clipboard");
        }
        function open(): void { ShellState.openPanel(ShellState.focusedScreen(), "clipboard"); }
        function close(): void { if (ShellState.panelModule === "clipboard") ShellState.closeAll(); }
    }

    // Движок запоминает скопированное с начала сеанса, а не с первого
    // открытия истории. Остановить его можно только с процессом оболочки —
    // поэтому "restartOnDisable" в module.json.
    Component.onCompleted: ClipboardState.count
}
