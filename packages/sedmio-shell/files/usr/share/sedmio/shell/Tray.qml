import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import Sedmio.Style

// Значки программ в трее (StatusNotifierItem) — столбиком (полоса слева)
// или в строку (верхняя панель). Пассивные — скрыты. Меню значка — справа
// от полосы или под верхней панелью.
Grid {
    id: tray
    required property var window
    required property Item tooltip
    property bool horizontal: false

    rows: horizontal ? 1 : -1
    columns: horizontal ? -1 : 1
    spacing: horizontal ? 2 : 0

    Repeater {
        model: SystemTray.items

        BarButton {
            id: item
            required property var modelData
            implicitHeight: tray.horizontal ? Theme.buttonSize : 34
            visible: modelData.status !== Status.Passive
            tooltip: tray.tooltip
            hint: modelData.tooltipTitle || modelData.title || modelData.id

            onClicked: event => {
                if (event.button === Qt.RightButton || (modelData.onlyMenu && modelData.hasMenu)) {
                    const p = tray.horizontal ? item.mapToItem(null, 0, item.height + 8)
                                              : item.mapToItem(null, item.width + 8, 0);
                    modelData.display(tray.window, p.x, p.y);
                } else if (event.button === Qt.MiddleButton) {
                    modelData.secondaryActivate();
                } else {
                    modelData.activate();
                }
            }
            onWheel: event => modelData.scroll(event.angleDelta.y, false)

            IconImage {
                anchors.centerIn: parent
                implicitSize: 20
                source: Icons.themed(item.modelData.icon)
            }
        }
    }
}
