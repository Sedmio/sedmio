pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Wayland

// Общее состояние оболочки: что открыто и на каком экране.
// Запуск программ, панель управления, центр уведомлений и буфер обмена
// открываются по одному: открыв одно, закрываем другое.
Singleton {
    id: root

    // Кнопка панели, у которой открыты миниатюры окон (WindowButton):
    // соседняя кнопка открывает свои сразу, закрыв эти.
    property var previewOwner: null

    // Имя экрана, на котором открыт запуск программ; "" — закрыт.
    property string launcherScreen: ""
    // То же для панели управления и центра уведомлений.
    property string controlScreen: ""
    // Раздел панели управления — у каждой кнопки панели свой:
    // "network" (сеть), "brightness" (яркость), "sound" (звук),
    // "calendar" (часы), "battery" (батарея); "bluetooth" — из плитки
    // в Пуске.
    property string controlSection: "calendar"
    property string notificationsScreen: ""
    property string clipboardScreen: ""
    // Меню быстрых ссылок (Win+X, QuickMenu.qml).
    property string quickMenuScreen: ""

    readonly property bool anythingOpen: launcherScreen !== "" || controlScreen !== ""
        || notificationsScreen !== "" || clipboardScreen !== "" || quickMenuScreen !== ""

    // Сколько открыто меню и списков окон у кнопок панелей: пока открыты,
    // док не прячется (меню прикреплены к его кнопкам).
    property int panelMenus: 0

    // Окно, активное до открытия. Пока открыт запуск или панель, клавиатура
    // у оболочки; отпустив её, KWin сам фокус не возвращает — возвращаем.
    property var windowBefore: null

    // «Показать рабочий стол» KWin: прячет все окна, повторный вызов —
    // возвращает.
    function showDesktop() {
        Quickshell.execDetached(["busctl", "--user", "call", "org.kde.kglobalaccel",
            "/component/kwin", "org.kde.kglobalaccel.Component", "invokeShortcut", "s", "Show Desktop"]);
    }

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

    // Нажали кнопку открытого раздела — закрыть; другого — переключить
    // на месте, не закрывая панель.
    function toggleControl(screenName, section) {
        if (controlScreen === screenName && controlSection === section) closeAll();
        else openControl(screenName, section);
    }

    function openControl(screenName, section) {
        rememberFocus();
        quickMenuScreen = "";
        launcherScreen = "";
        notificationsScreen = "";
        clipboardScreen = "";
        controlSection = section;
        controlScreen = screenName;
    }

    function controlShows(screenName, section) {
        return controlScreen === screenName && controlSection === section;
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

    // Программы на панели: [{key, entry, pinned, windows: [toplevel…]}].
    // Сначала закреплённые (PinnedApps) в своём порядке, даже без окон,
    // потом остальные запущенные в порядке появления; окна одной
    // программы — вместе. key — у закреплённой имя .desktop-файла, у
    // остальных appId окна (нет его — заголовок). Диалоги (у окна есть родитель) не считаем — они
    // поднимаются вместе со своим окном. Окна других рабочих столов тоже,
    // как в Windows (inCurrentDesktop — из нашего патча Quickshell; без него
    // undefined — окно показываем).
    // Здесь, а не в панели: по этому же порядку работают Meta+1…9.
    // Порядок незакреплённых запущенных программ, заданный перетаскиванием
    // на панели (ключи групп). Живёт, пока работает оболочка; новые
    // программы — в конец.
    property var runningOrder: []

    readonly property var windowGroups: {
        // .desktop-файлы Quickshell читает в фоне: пересчитать, когда дочитал.
        if (DesktopEntries.applications.values.length < 0) return [];
        const byKey = {};
        const result = [];
        for (const id of PinnedApps.ids) {
            const entry = DesktopEntries.byId(id);
            if (!entry || byKey[entry.id]) continue;   // не установлена
            byKey[entry.id] = { key: entry.id, entry: entry, pinned: true, windows: [] };
            result.push(byKey[entry.id]);
        }
        for (const t of ToplevelManager.toplevels.values) {
            if (t.parent || t.inCurrentDesktop === false) continue;
            const entry = t.appId ? DesktopEntries.heuristicLookup(t.appId) : null;
            // К закреплённой — по найденному .desktop; остальные — по appId:
            // догадка heuristicLookup могла бы склеить разные программы.
            const key = entry && byKey[entry.id]?.pinned ? entry.id : (t.appId || t.title);
            if (!byKey[key]) {
                byKey[key] = { key: key, entry: entry, pinned: false, windows: [] };
                result.push(byKey[key]);
            }
            byKey[key].windows.push(t);
        }
        // Незакреплённые — в порядке runningOrder, новые за ними.
        const pinned = result.filter(g => g.pinned);
        const running = result.filter(g => !g.pinned);
        const ordered = runningOrder.map(k => running.find(g => g.key === k)).filter(g => !!g);
        return pinned.concat(ordered, running.filter(g => !ordered.includes(g)));
    }

    // Запустить программу с панели (закреплённую или ещё одно окно).
    function launchGroup(group) {
        if (!group || !group.entry) return;
        if (anythingOpen) closeAll(false);
        AppSearch.launch(group.entry, false);
    }

    // Meta+1…9 (usr/share/kglobalaccel/sedmio-windows.desktop): показать
    // программу с этим номером на панели, как в Windows. Не запущена
    // (закреплённая) — запустить. Уже активна: одно окно — свернуть,
    // несколько — показать следующее.
    function activateGroup(index) {
        const group = windowGroups[index];
        if (!group) return;
        if (anythingOpen) closeAll(false);
        const windows = group.windows;
        if (windows.length === 0) {
            launchGroup(group);
            return;
        }
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
            && active.screens[0]?.name === screenName;
    }

    // Экран, с которым сейчас работают: тот, где активное окно.
    // Для клавиш (Meta), у которых своего экрана нет.
    function focusedScreen() {
        const active = ToplevelManager.activeToplevel;
        // Экран окна бывает null: Quickshell ещё не знает этот экран
        // (только что подключили) — тогда как без окна.
        const name = active && active.screens.length > 0 ? active.screens[0]?.name : "";
        if (name) return name;
        return Quickshell.screens.length > 0 ? Quickshell.screens[0].name : "";
    }
}
