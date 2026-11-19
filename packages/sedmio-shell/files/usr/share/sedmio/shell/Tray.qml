import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets

// Значки программ в трее (StatusNotifierItem). Пассивные — скрыты.
ColumnLayout {
    id: tray
    required property var window
    required property Item tooltip
    spacing: 0

    Repeater {
        model: SystemTray.items

        BarButton {
            id: item
            required property var modelData
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredHeight: 34
            visible: modelData.status !== Status.Passive
            tooltip: tray.tooltip
            hint: modelData.tooltipTitle || modelData.title || modelData.id

            onClicked: event => {
                if (event.button === Qt.RightButton || (modelData.onlyMenu && modelData.hasMenu)) {
                    const p = item.mapToItem(null, item.width + 8, 0);
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
