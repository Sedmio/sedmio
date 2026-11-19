import QtQuick
import Quickshell

// Меню по правому клику на рабочем столе (Wallpaper.qml), как в Windows.
// Параметры открываются через open-settings: без «Параметров» Sedmio —
// раздел параметров KDE.
ContextMenu {
    id: menu
    required property var window

    items: [
        { icon: "preferences-desktop-wallpaper", text: "Сменить обои", action: "wallpaper" },
        { icon: "preferences-desktop-display", text: "Параметры экрана", action: "display" },
        { icon: "utilities-terminal", text: "Терминал", action: "terminal" },
        { separator: true },
        { icon: "preferences-system", text: "Параметры", action: "settings" },
    ]

    readonly property var commands: ({
        wallpaper: ["/usr/lib/sedmio/open-settings", "wallpaper"],
        display: ["/usr/lib/sedmio/open-settings", "display", "kcm_kscreen"],
        terminal: ["ghostty", "--gtk-single-instance=true"],
        settings: ["/usr/lib/sedmio/open-settings"],
    })

    function openAt(x, y) {
        ShellState.closeAll();
        anchor.rect.x = x;
        anchor.rect.y = y;
        visible = true;
    }

    onTriggered: action => {
        const command = commands[action];
        if (command) ShellState.launch("", command);
    }

    anchor.window: window
    anchor.rect.width: 1
    anchor.rect.height: 1
    anchor.edges: Edges.Bottom | Edges.Right
    anchor.gravity: Edges.Bottom | Edges.Right
}
