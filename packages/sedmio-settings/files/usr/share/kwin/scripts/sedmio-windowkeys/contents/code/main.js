// Клавиши окон как в Windows (пакет sedmio-settings): Win+↑, Win+↓, Alt+F4
// на пустом рабочем столе, фокус после Win+D. Клавиши у KWin по умолчанию
// заняты его действиями — их отдаёт этим kconf_update
// (usr/share/kconf_update/sedmio-windowkeys.sh) один раз.

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
