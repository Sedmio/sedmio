import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import Sedmio.Style

// Значки программ в трее (StatusNotifierItem) — столбиком (полоса слева)
// или в строку (верхняя панель). Пассивные — скрыты. Меню значка (своё,
// TrayMenu) — справа от полосы или под верхней панелью. У значков без
// dbusmenu — старых программ X11 через xembedsniproxy — правый щелчок
// уходит самой программе (ContextMenu), и меню показывает она.
Grid {
    id: tray
    required property var window
    required property Item tooltip
    property bool horizontal: false
    property real buttonSize: Theme.buttonSize

    rows: horizontal ? 1 : -1
    columns: horizontal ? -1 : 1
    spacing: horizontal ? 2 : 0

    Repeater {
        model: SystemTray.items

        BarButton {
            id: item
            required property var modelData
            size: tray.buttonSize
            implicitHeight: tray.horizontal ? size : size - 2
            visible: modelData.status !== Status.Passive
            hint: modelData.tooltipTitle || modelData.title || modelData.id

            tooltip: trayMenu.visible ? null : tray.tooltip
            active: trayMenu.visible

            // Середина значка на экране (общие координаты всех экранов):
            // xembedsniproxy щёлкает по значку программы там, и её меню
            // появляется у трея.
            function screenPoint() {
                const p = item.mapToItem(null, item.width / 2, item.height / 2);
                const screen = tray.window.screen;
                return Qt.point(Math.round((screen?.x ?? 0) + p.x), Math.round((screen?.y ?? 0) + p.y));
            }

            onClicked: event => {
                const g = screenPoint();
                if (event.button === Qt.RightButton || (modelData.onlyMenu && modelData.hasMenu)) {
                    if (modelData.hasMenu) {
                        if (tray.tooltip) tray.tooltip.hide();
                        if (trayMenu.visible) trayMenu.visible = false;
                        else trayMenu.open();
                    } else {
                        modelData.contextMenu(g.x, g.y);
                    }
                } else if (event.button === Qt.MiddleButton) {
                    modelData.secondaryActivate(g.x, g.y);
                } else {
                    modelData.activate(g.x, g.y);
                }
            }
            onWheel: event => modelData.scroll(event.angleDelta.y, false)

            IconImage {
                anchors.centerIn: parent
                implicitSize: item.iconSize
                source: Icons.themed(item.modelData.icon)
            }

            TrayMenu {
                id: trayMenu
                handle: item.modelData.hasMenu ? item.modelData.menu : null
                anchor.item: item
                anchor.rect.y: tray.horizontal ? 8 : 0
                anchor.rect.width: tray.horizontal ? item.width : item.width + 8
                anchor.rect.height: item.height
                // Под верхней панелью — влево от значка (трей у правого
                // края), у полосы слева — вправо и вниз.
                anchor.edges: tray.horizontal ? Edges.Bottom | Edges.Right : Edges.Right | Edges.Top
                anchor.gravity: tray.horizontal ? Edges.Bottom | Edges.Left : Edges.Right | Edges.Bottom
                onVisibleChanged: ShellState.panelMenus += visible ? 1 : -1
                Component.onDestruction: if (visible) ShellState.panelMenus -= 1
            }
        }
    }
}
