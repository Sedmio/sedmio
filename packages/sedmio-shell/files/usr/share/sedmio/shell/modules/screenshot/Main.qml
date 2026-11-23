import QtQuick
import Quickshell
import Quickshell.Io

// «Ножницы»: PrtSc, Win+Shift+S (/usr/lib/sedmio/screenshot из
// sedmio-settings) —
//   quickshell ipc -p /usr/share/sedmio/shell call screenshot open
// Модуль выключен — этой цели нет, и PrtSc снимает все экраны сразу.
Scope {
    IpcHandler {
        target: "screenshot"
        function open(): void { ScreenshotState.open(); }
        function close(): void { ScreenshotState.close(); }
    }
}
