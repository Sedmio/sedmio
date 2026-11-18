pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Wayland

// Общее состояние оболочки: что открыто и на каком экране.
// Запуск программ, панель управления, центр уведомлений и буфер обмена
// открываются по одному: открыв одно, закрываем другое.
Singleton {
    id: root

    // Имя экрана, на котором открыт запуск программ; "" — закрыт.
    property string launcherScreen: ""
    // То же для панели управления и центра уведомлений.
    property string controlScreen: ""
    property string notificationsScreen: ""
    property string clipboardScreen: ""

    readonly property bool anythingOpen: launcherScreen !== "" || controlScreen !== ""
        || notificationsScreen !== "" || clipboardScreen !== ""

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
        clipboardScreen = "";
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
        clipboardScreen = "";
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
        clipboardScreen = "";
        notificationsScreen = screenName;
        NotificationState.markRead();
    }

    function toggleClipboard(screenName) {
        if (clipboardScreen === screenName) closeAll();
        else openClipboard(screenName);
    }

    function openClipboard(screenName) {
        rememberFocus();
        launcherScreen = "";
        controlScreen = "";
        notificationsScreen = "";
        clipboardScreen = screenName;
    }

    // restoreFocus: false — когда запустили программу, фокус получит она.
    function closeAll(restoreFocus) {
        if (!anythingOpen) return;
        launcherScreen = "";
        controlScreen = "";
        notificationsScreen = "";
        clipboardScreen = "";
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

    // Сопрячь устройство Bluetooth, а сопряглось — доверять ему и подключить.
    // Здесь, а не в панели: на время запроса кода панель закрывается.
    property var pairingDevice: null

    function pairAndConnect(device) {
        pairingDevice = device;
        device.pair();
    }

    Connections {
        target: root.pairingDevice
        function onPairedChanged() {
            const device = root.pairingDevice;
            if (!device.paired) return;
            root.pairingDevice = null;
            device.trusted = true;
            device.connect();
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
