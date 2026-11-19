// Win+↑ и Win+↓ как в Windows (пакет sedmio-settings). Клавиши у KWin по
// умолчанию заняты «прилепить к верху/низу» — их отдаёт этим действиям
// kconf_update (usr/share/kconf_update/sedmio-windowkeys.sh) один раз.

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
        w.tile = null;
    else if (w.minimizable)
        w.minimized = true;
});
