import QtQuick
import Quickshell

// Правый щелчок по пустому месту панели — меню, как у панели задач
// Windows. Кладётся под кнопки панели: их щелчки до него не доходят.
MouseArea {
    id: root
    required property var window     // окно рамки
    acceptedButtons: Qt.RightButton

    onClicked: event => {
        const p = mapToItem(null, event.x, event.y);
        // Меню — от щелчка внутрь экрана: у нижней панели вверх.
        const up = p.y > root.window.height / 2;
        menu.anchor.rect.x = p.x;
        menu.anchor.rect.y = p.y;
        menu.anchor.edges = (up ? Edges.Top : Edges.Bottom) | Edges.Right;
        menu.anchor.gravity = (up ? Edges.Top : Edges.Bottom) | Edges.Right;
        menu.visible = true;
    }

    Connections {
        target: menu
        function onVisibleChanged() { ShellState.panelMenus += menu.visible ? 1 : -1; }
    }
    Component.onDestruction: if (menu.visible) ShellState.panelMenus -= 1

    ContextMenu {
        id: menu
        anchor.window: root.window
        anchor.rect.width: 1
        anchor.rect.height: 1
        items: [
            { icon: "utilities-system-monitor", text: "Диспетчер задач", action: "tasks" },
            { icon: "user-desktop", text: "Показать рабочий стол", action: "desktop" },
            { separator: true },
            { icon: "preferences-system", text: "Параметры", action: "settings" },
        ]
        onTriggered: action => {
            ShellState.closeAll(false);
            if (action === "tasks") ShellState.launch("sedmio-tasks", ["sedmio-tasks"]);
            else if (action === "settings") ShellState.launch("", ["/usr/lib/sedmio/open-settings"]);
            else if (action === "desktop") Quickshell.execDetached(["busctl", "--user", "call", "org.kde.kglobalaccel",
                "/component/kwin", "org.kde.kglobalaccel.Component", "invokeShortcut", "s", "Show Desktop"]);
        }
    }
}
