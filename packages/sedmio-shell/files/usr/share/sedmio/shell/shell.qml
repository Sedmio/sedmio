// Оболочка Sedmio: обои, рамка вокруг экрана и панель слева.
// Запускается службой sedmio-shell.service вместо plasmashell.
import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    Variants {
        model: Quickshell.screens

        Scope {
            id: perScreen
            required property var modelData

            Wallpaper { screen: perScreen.modelData }
            Exclusions { screen: perScreen.modelData }
            Frame { screen: perScreen.modelData }
        }
    }

    // Заставка входа (KSplash) ждёт сигнала «рабочий стол готов»,
    // который раньше посылал plasmashell. Без него она висит до таймаута.
    Process {
        running: true
        command: ["busctl", "--user", "call", "org.kde.KSplash", "/KSplash",
                  "org.kde.KSplash", "setStage", "s", "desktop"]
    }
}
