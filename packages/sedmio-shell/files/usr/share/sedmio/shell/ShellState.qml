pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Wayland

// Общее состояние оболочки: что открыто и на каком экране.
Singleton {
    // Имя экрана, на котором открыт запуск программ; "" — закрыт.
    property string launcherScreen: ""

    // Окно, активное до открытия запуска. Пока запуск открыт, клавиатура
    // у оболочки; отпустив её, KWin сам фокус не возвращает — возвращаем.
    property var windowBeforeLauncher: null

    function toggleLauncher(screenName) {
        if (launcherScreen === screenName) closeLauncher();
        else openLauncher(screenName);
    }

    function openLauncher(screenName) {
        if (launcherScreen === "") windowBeforeLauncher = ToplevelManager.activeToplevel;
        launcherScreen = screenName;
    }

    // restoreFocus: false — когда запустили программу, фокус получит она.
    function closeLauncher(restoreFocus) {
        if (launcherScreen === "") return;
        launcherScreen = "";
        if (restoreFocus !== false && windowBeforeLauncher) windowBeforeLauncher.activate();
        windowBeforeLauncher = null;
    }

    // Экран, с которым сейчас работают: тот, где активное окно.
    // Для клавиш (Meta), у которых своего экрана нет.
    function focusedScreen() {
        const active = ToplevelManager.activeToplevel;
        if (active && active.screens.length > 0) return active.screens[0].name;
        return Quickshell.screens.length > 0 ? Quickshell.screens[0].name : "";
    }
}
