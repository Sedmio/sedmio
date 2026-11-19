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
    // Меню быстрых ссылок (Win+X, QuickMenu.qml).
    property string quickMenuScreen: ""

    readonly property bool anythingOpen: launcherScreen !== "" || controlScreen !== ""
        || notificationsScreen !== "" || clipboardScreen !== "" || quickMenuScreen !== ""

    // Окно, активное до открытия. Пока открыт запуск или панель, клавиатура
    // у оболочки; отпустив её, KWin сам фокус не возвращает — возвращаем.
    property var windowBefore: null

    // Запустить программу в своей группе systemd (/usr/lib/sedmio/launch):
    // упадёт или перезапустится оболочка — программа живёт дальше.
    // id — имя .desktop без расширения ("" — по имени команды).
    function launch(id, command, workingDirectory) {
        const args = ["/usr/lib/sedmio/launch", id || ""];
        for (let i = 0; i < command.length; i++) args.push(command[i]);
        if (workingDirectory) Quickshell.execDetached({ command: args, workingDirectory: workingDirectory });
        else Quickshell.execDetached(args);
    }

    function rememberFocus() {
        if (!anythingOpen) windowBefore = ToplevelManager.activeToplevel;
    }

    function toggleLauncher(screenName) {
        if (launcherScreen === screenName) closeAll();
        else openLauncher(screenName);
    }

    function openLauncher(screenName) {
        rememberFocus();
        quickMenuScreen = "";
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
        quickMenuScreen = "";
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
        quickMenuScreen = "";
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
        quickMenuScreen = "";
        launcherScreen = "";
        controlScreen = "";
        notificationsScreen = "";
        clipboardScreen = screenName;
    }

    function toggleQuickMenu(screenName) {
        if (quickMenuScreen === screenName) closeAll();
        else openQuickMenu(screenName);
    }

    function openQuickMenu(screenName) {
        rememberFocus();
        launcherScreen = "";
        controlScreen = "";
        notificationsScreen = "";
        clipboardScreen = "";
        quickMenuScreen = screenName;
    }

    // restoreFocus: false — когда запустили программу, фокус получит она.
    function closeAll(restoreFocus) {
        if (!anythingOpen) return;
        launcherScreen = "";
        controlScreen = "";
        notificationsScreen = "";
        clipboardScreen = "";
        quickMenuScreen = "";
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

    // Программы на панели: [{key, windows: [toplevel…]}] в порядке
    // появления, окна одной программы — вместе. Диалоги (у окна есть
    // родитель) не считаем — они поднимаются вместе со своим окном.
    // Здесь, а не в панели: по этому же порядку работают Meta+1…9.
    readonly property var windowGroups: {
        const byKey = {};
        const result = [];
        for (const t of ToplevelManager.toplevels.values) {
            if (t.parent) continue;
            const key = t.appId || t.title;
            if (!byKey[key]) {
                byKey[key] = { key: key, windows: [] };
                result.push(byKey[key]);
            }
            byKey[key].windows.push(t);
        }
        return result;
    }

    // Meta+1…9 (usr/share/kglobalaccel/sedmio-windows.desktop): показать
    // программу с этим номером на панели, как в Windows. Она уже активна:
    // одно окно — свернуть, несколько — показать следующее.
    function activateGroup(index) {
        const group = windowGroups[index];
        if (!group) return;
        if (anythingOpen) closeAll(false);
        const windows = group.windows;
        const current = windows.findIndex(w => w.activated);
        if (current < 0) windows[0].activate();
        else if (windows.length === 1) windows[0].minimized = true;
        else windows[(current + 1) % windows.length].activate();
    }

    // Активное окно во весь экран на этом экране (видео, игра): рамка
    // оболочки под ним — то, что нельзя пропустить, показываем поверх.
    // Экран окна — первый, как в focusedScreen(): окно задело край соседнего
    // экрана — плашка всё равно одна, там же, где уведомления и громкость.
    function fullscreenOn(screenName) {
        const active = ToplevelManager.activeToplevel;
        return !!active && active.fullscreen && active.screens.length > 0
            && active.screens[0].name === screenName;
    }

    // Экран, с которым сейчас работают: тот, где активное окно.
    // Для клавиш (Meta), у которых своего экрана нет.
    function focusedScreen() {
        const active = ToplevelManager.activeToplevel;
        if (active && active.screens.length > 0) return active.screens[0].name;
        return Quickshell.screens.length > 0 ? Quickshell.screens[0].name : "";
    }
}
