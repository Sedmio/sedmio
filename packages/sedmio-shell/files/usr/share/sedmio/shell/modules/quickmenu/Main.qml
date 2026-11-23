import QtQuick
import Quickshell
import Quickshell.Io
import qs

// Meta+X (usr/share/kglobalaccel/sedmio-quickmenu.desktop).
Scope {
    IpcHandler {
        target: "quickmenu"
        function toggle(): void {
            if (ShellState.quickMenuScreen !== "") ShellState.closeAll();
            else ShellState.openQuickMenu(ShellState.focusedScreen());
        }
        function open(): void { ShellState.openQuickMenu(ShellState.focusedScreen()); }
        function close(): void { ShellState.closeAll(); }
    }
}
