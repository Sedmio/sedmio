// Оболочка Sedmio: обои, рамка вокруг экрана и панель слева.
// Запускается службой sedmio-shell.service вместо plasmashell.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Kde

ShellRoot {
    id: root
    // За файлами не следим: pacman обновляет их по одному, и оболочка
    // перечитала бы недописанный набор («Config reload failed» и старая
    // версия до перезахода). Перечитывает хук pacman, когда все файлы на
    // месте (usr/share/libalpm/hooks/sedmio-shell-reload.hook):
    //   quickshell ipc -p /usr/share/sedmio/shell call shell reload
    settings.watchFiles: false

    IpcHandler {
        target: "shell"
        function reload(): void { Quickshell.reload(false); }
        // Окно пароля (служба sedmio-agents) открылось — меню и панели убрать.
        function closePopups(): void { ShellState.closeAll(false); }
    }

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

    // Команды извне: клавиши Meta и Alt+F1 (usr/share/kglobalaccel/sedmio-launcher.desktop) —
    //   quickshell ipc -p /usr/share/sedmio/shell call launcher toggle
    IpcHandler {
        target: "launcher"
        function toggle(): void {
            if (ShellState.launcherScreen !== "") ShellState.closeAll();
            else ShellState.openLauncher(ShellState.focusedScreen());
        }
        function open(): void { ShellState.openLauncher(ShellState.focusedScreen()); }
        function close(): void { ShellState.closeAll(); }
    }

    // Панель управления: клавиши Meta+A (usr/share/kglobalaccel/sedmio-control.desktop) —
    //   quickshell ipc -p /usr/share/sedmio/shell call control toggle
    IpcHandler {
        target: "control"
        function toggle(): void {
            if (ShellState.controlScreen !== "") ShellState.closeAll();
            else ShellState.openControl(ShellState.focusedScreen());
        }
        function open(): void { ShellState.openControl(ShellState.focusedScreen()); }
        function close(): void { ShellState.closeAll(); }
    }

    // Центр уведомлений: Meta+N (usr/share/kglobalaccel/sedmio-notifications.desktop).
    IpcHandler {
        target: "notifications"
        function toggle(): void {
            if (ShellState.notificationsScreen !== "") ShellState.closeAll();
            else ShellState.openNotifications(ShellState.focusedScreen());
        }
        function open(): void { ShellState.openNotifications(ShellState.focusedScreen()); }
        function close(): void { ShellState.closeAll(); }
        function clear(): void { NotificationState.clearAll(); }
    }

    // История буфера обмена: Meta+V (usr/share/kglobalaccel/sedmio-clipboard.desktop).
    IpcHandler {
        target: "clipboard"
        function toggle(): void {
            if (ShellState.clipboardScreen !== "") ShellState.closeAll();
            else ShellState.openClipboard(ShellState.focusedScreen());
        }
        function open(): void { ShellState.openClipboard(ShellState.focusedScreen()); }
        function close(): void { ShellState.closeAll(); }
    }

    // Программы на панели по номеру: Meta+1…9
    // (usr/share/kglobalaccel/sedmio-windows.desktop).
    IpcHandler {
        target: "windows"
        function activate(number: int): void { ShellState.activateGroup(number - 1); }
    }

    // Всплывающие индикаторы: служба org.kde.osdService вместо plasmashell.
    // Её вызывают kded (клавиши громкости, плееры), powerdevil (яркость),
    // KWin (раскладка).
    OsdServer {
        onProgress: (kind, icon, percent, maximum, label) => OsdState.progress(kind, icon, percent, maximum, label)
        onMessage: (kind, icon, text) => {
            if (kind === "powerProfile") OsdState.powerProfile(text);
            else OsdState.message(kind, icon, text);
        }
        onToggled: (kind, enabled) => OsdState.toggled(kind, enabled)
        onHideRequested: OsdState.hide()
    }

    // Окна паролей (администратор, Wi‑Fi, сопряжение Bluetooth) — не здесь,
    // а в отдельном процессе: служба sedmio-agents.service,
    // /usr/share/sedmio/agents. Упадёт оболочка — пароли спрашиваются.

    // Модули kded, чью работу делает оболочка (агент паролей Wi‑Fi из
    // plasma-nm, просьба о пожертвованиях), не загружаются вовсе —
    // /etc/xdg/kded5rc. Выгружать их на ходу нельзя: kded6 от этого падает.

    // Сервер уведомлений живёт в NotificationState, движок буфера обмена —
    // в ClipboardState, сервер заданий (ход копирования файлов) — в JobsState;
    // обращение запускает их сразу, а не при первом показе.
    Component.onCompleted: {
        NotificationState.popups;
        ClipboardState.count;
        JobsState.active;
    }

    // Заставка входа (KSplash) ждёт сигнала «рабочий стол готов»,
    // который раньше посылал plasmashell. Без него она висит до таймаута.
    // Шлём, когда обои уже на экране (картинка грузится не сразу), но не
    // позже чем через 4 секунды.
    Process {
        id: splashDone
        command: ["busctl", "--user", "call", "org.kde.KSplash", "/KSplash",
                  "org.kde.KSplash", "setStage", "s", "desktop"]
    }
    property bool splashSent: false
    function sendSplashDone() {
        if (splashSent) return;
        splashSent = true;
        splashDone.running = true;
    }
    Connections {
        target: WallpaperState
        function onShownChanged() { if (WallpaperState.shown) root.sendSplashDone(); }
    }
    Timer {
        interval: 4000
        running: true
        onTriggered: root.sendSplashDone()
    }
}
