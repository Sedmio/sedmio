pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Wayland

// Общее состояние оболочки: что открыто и на каком экране.
// Запуск программ, панель управления и центр уведомлений открываются по
// одному: открыв одно, закрываем другое.
Singleton {
    id: root

    // Имя экрана, на котором открыт запуск программ; "" — закрыт.
    property string launcherScreen: ""
    // То же для панели управления и центра уведомлений.
    property string controlScreen: ""
    property string notificationsScreen: ""

    readonly property bool anythingOpen: launcherScreen !== "" || controlScreen !== "" || notificationsScreen !== ""

    // Окно, активное до открытия. Пока открыт запуск или панель, клавиатура
    // у оболочки; отпустив её, KWin сам фокус не возвращает — возвращаем.
    property var windowBefore: null

    function rememberFocus() {
        if (!anythingOpen) windowBefore = ToplevelManager.activeToplevel;
    }

    function toggleLauncher(screenName) {
        if (launcherScreen === screenName) closeAll();
        else openLauncher(screenName);
    }

    function openLauncher(screenName) {
        rememberFocus();
        controlScreen = "";
        notificationsScreen = "";
        launcherScreen = screenName;
    }

    function toggleControl(screenName) {
        if (controlScreen === screenName) closeAll();
        else openControl(screenName);
    }

    function openControl(screenName) {
        rememberFocus();
        launcherScreen = "";
        notificationsScreen = "";
        controlScreen = screenName;
    }

    function toggleNotifications(screenName) {
        if (notificationsScreen === screenName) closeAll();
        else openNotifications(screenName);
    }

    function openNotifications(screenName) {
        rememberFocus();
        launcherScreen = "";
        controlScreen = "";
        notificationsScreen = screenName;
        NotificationState.markRead();
    }

    // restoreFocus: false — когда запустили программу, фокус получит она.
    function closeAll(restoreFocus) {
        if (!anythingOpen) return;
        launcherScreen = "";
        controlScreen = "";
        notificationsScreen = "";
        if (restoreFocus !== false && windowBefore) windowBefore.activate();
        windowBefore = null;
    }

    // Появилось новое окно (диалог пароля Wi‑Fi, окно программы), пока
    // открыт запуск или панель: уступить ему клавиатуру, иначе в него не
    // напечатать — пока панель открыта, клавиатура у оболочки.
    Connections {
        target: ToplevelManager.toplevels
        function onObjectInsertedPost(object, index) {
            if (!root.anythingOpen) return;
            root.closeAll(false);
            Qt.callLater(() => object.activate());
        }
    }

    // Экран, с которым сейчас работают: тот, где активное окно.
    // Для клавиш (Meta), у которых своего экрана нет.
    function focusedScreen() {
        const active = ToplevelManager.activeToplevel;
        if (active && active.screens.length > 0) return active.screens[0].name;
        return Quickshell.screens.length > 0 ? Quickshell.screens[0].name : "";
    }
}
