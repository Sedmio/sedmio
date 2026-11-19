import QtQuick
import Quickshell.Widgets
import Sedmio.Style

// Быстрые настройки: Bluetooth, «Не беспокоить», режим питания (раздел
// "settings" панели управления, Meta+A).
BarButton {
    id: root
    required property string screenName
    active: ShellState.controlShows(screenName, "settings")
    hint: "Быстрые настройки"
    onClicked: { if (tooltip) tooltip.hide(); ShellState.toggleControl(screenName, "settings"); }

    IconImage {
        anchors.centerIn: parent
        implicitSize: 20
        source: Icons.path("configure")
    }
}
