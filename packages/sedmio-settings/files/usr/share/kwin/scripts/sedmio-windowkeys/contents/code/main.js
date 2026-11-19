// Клавиши окон как в Windows (пакет sedmio-settings): Win+↑, Win+↓, Alt+F4
// на пустом рабочем столе, фокус после Win+D, Win+M, Win+Home,
// Win+Shift+↑, Win+Ctrl+D и Win+Ctrl+F4. Клавиши Win+↑, Win+↓ и Alt+F4 у
// KWin по умолчанию заняты его действиями — их отдаёт этим kconf_update
// (usr/share/kconf_update/sedmio-windowkeys.sh) один раз; остальные
// свободны и достаются действиям сами.

function usable(w) {
    return w && w.normalWindow && !w.fullScreen;
}

// Win+↑ — развернуть (и прилепленное к краю тоже).
registerShortcut("Sedmio Window Up", "Развернуть окно (как Win+↑ в Windows)", "Meta+Up", function () {
    const w = workspace.activeWindow;
    if (usable(w) && w.maximizable)
        w.setMaximize(true, true);
});

// Win+↓ — развёрнутое или прилепленное вернуть к прежнему размеру,
// обычное — свернуть.
registerShortcut("Sedmio Window Down", "Вернуть размер или свернуть окно (как Win+↓ в Windows)", "Meta+Down", function () {
    const w = workspace.activeWindow;
    if (!usable(w))
        return;
    if (w.maximizeMode !== 0)
        w.setMaximize(false, false);
    else if (w.tile)
        w.tile.unmanage(w);
    else if (w.minimizable)
        w.minimized = true;
});

// Alt+F4 — закрыть окно, как раньше; окна нет (пустой рабочий стол, Win+D)
// — экран «Что сделать?» (выключить, перезагрузить, выйти), как
// «Завершение работы Windows». Без отсчёта: случайное Alt+F4 ничего не
// выключит.
registerShortcut("Sedmio Window Close", "Закрыть окно, а на пустом рабочем столе — завершение работы (как Alt+F4 в Windows)", "Alt+F4", function () {
    const w = workspace.activeWindow;
    if (w && !w.desktopWindow && !w.dock) {
        if (w.closeable)
            w.closeWindow();
        return;
    }
    callDBus("org.kde.LogoutPrompt", "/LogoutPrompt", "org.kde.LogoutPrompt", "promptAll");
});

// Win+D прячет окна, но активное остаётся активным: набранное уходило бы
// в спрятанное окно, а Alt+F4 закрыл бы его. Как в Windows, фокус —
// рабочему столу, то есть никому. Состояние «рабочий стол показан» скрипту
// не видно — спрашиваем KWin по D-Bus, когда окна прячутся или возвращаются.
// Ответ приходит позже: верим только ответу на последний вопрос и только
// если активное окно с тех пор то же (новое окно открылось сразу после
// Win+D — фокус остаётся ему).
let asked = 0;
function showDesktopChanged() {
    const question = ++asked;
    const before = workspace.activeWindow;
    callDBus("org.kde.KWin", "/KWin", "org.freedesktop.DBus.Properties", "Get",
             "org.kde.KWin", "showingDesktop", function (showing) {
        const w = workspace.activeWindow;
        if (question !== asked || w !== before)
            return;
        if (showing === true && w && !w.desktopWindow && !w.dock)
            workspace.activeWindow = null;
    });
}
function watch(w) {
    w.hiddenByShowDesktopChanged.connect(showDesktopChanged);
}
workspace.windowList().forEach(watch);
workspace.windowAdded.connect(watch);

// Окна текущего рабочего стола, какие показаны на панели, — снизу вверх.
function onCurrentDesktop(w) {
    return w.onAllDesktops || w.desktops.indexOf(workspace.currentDesktop) !== -1;
}
function taskWindows() {
    return workspace.stackingOrder.filter(function (w) {
        return w.normalWindow && !w.skipTaskbar && onCurrentDesktop(w);
    });
}

// Вернуть свёрнутые: снизу вверх, чтобы верхнее легло сверху, и
// отдать фокус тому, что было активным. Окна, которые с тех пор
// закрыли, развернули сами или унесли на другой стол, не трогаем.
function restore(list, active) {
    list.forEach(function (w) {
        if (w.minimized && onCurrentDesktop(w))
            w.minimized = false;
    });
    if (active && list.indexOf(active) !== -1 && !active.minimized)
        workspace.activeWindow = active;
}

// Win+M — свернуть все окна, Win+Shift+M — вернуть свёрнутые этим.
let minimizedAll = [];
let activeBeforeAll = null;
registerShortcut("Sedmio Minimize All", "Свернуть все окна (как Win+M в Windows)", "Meta+M", function () {
    const active = workspace.activeWindow;
    const list = taskWindows().filter(function (w) { return !w.minimized && w.minimizable; });
    if (list.length === 0)
        return;
    minimizedAll = list;
    activeBeforeAll = active;
    list.forEach(function (w) { w.minimized = true; });
});
registerShortcut("Sedmio Restore All", "Вернуть окна, свёрнутые Win+M (как Win+Shift+M в Windows)", "Meta+Shift+M", function () {
    const list = minimizedAll;
    minimizedAll = [];
    restore(list, activeBeforeAll);
    activeBeforeAll = null;
});

// Win+Home — свернуть все окна, кроме активного; ещё раз — вернуть.
let minimizedOthers = [];
let keptWindow = null;
registerShortcut("Sedmio Minimize Others", "Свернуть все окна, кроме активного; ещё раз — вернуть (как Win+Home в Windows)", "Meta+Home", function () {
    const active = workspace.activeWindow;
    if (keptWindow && keptWindow === active
        && minimizedOthers.some(function (w) { return w.minimized; })) {
        const list = minimizedOthers;
        minimizedOthers = [];
        keptWindow = null;
        restore(list, null);
        workspace.activeWindow = active;
        return;
    }
    if (!usable(active))
        return;
    minimizedOthers = taskWindows().filter(function (w) {
        return w !== active && !w.minimized && w.minimizable;
    });
    keptWindow = active;
    minimizedOthers.forEach(function (w) { w.minimized = true; });
});

// Закрытые окна — из списков «что вернуть».
workspace.windowRemoved.connect(function (w) {
    minimizedAll = minimizedAll.filter(function (x) { return x !== w; });
    minimizedOthers = minimizedOthers.filter(function (x) { return x !== w; });
    if (activeBeforeAll === w)
        activeBeforeAll = null;
    if (keptWindow === w)
        keptWindow = null;
});

// Win+Shift+↑ — растянуть окно по высоте, ширина та же;
// Win+Shift+↓ — вернуть высоту.
registerShortcut("Sedmio Window Stretch", "Растянуть окно по высоте экрана (как Win+Shift+↑ в Windows)", "Meta+Shift+Up", function () {
    const w = workspace.activeWindow;
    if (usable(w) && w.maximizable)
        w.setMaximize(true, (w.maximizeMode & 2) !== 0);
});
registerShortcut("Sedmio Window Unstretch", "Вернуть высоту окна (как Win+Shift+↓ в Windows)", "Meta+Shift+Down", function () {
    const w = workspace.activeWindow;
    if (usable(w) && (w.maximizeMode & 1) !== 0)
        w.setMaximize(false, (w.maximizeMode & 2) !== 0);
});

// Win+Ctrl+D — новый рабочий стол (в конце) и перейти на него;
// Win+Ctrl+F4 — закрыть текущий: его окна KWin переносит на соседний.
// Последний стол не закрываем.
registerShortcut("Sedmio New Desktop", "Создать рабочий стол (как Win+Ctrl+D в Windows)", "Meta+Ctrl+D", function () {
    const count = workspace.desktops.length;
    if (count >= 20)
        return;
    workspace.createDesktop(count, "");
    if (workspace.desktops.length > count)
        workspace.currentDesktop = workspace.desktops[workspace.desktops.length - 1];
});
registerShortcut("Sedmio Close Desktop", "Закрыть рабочий стол (как Win+Ctrl+F4 в Windows)", "Meta+Ctrl+F4", function () {
    if (workspace.desktops.length > 1)
        workspace.removeDesktop(workspace.currentDesktop);
});
