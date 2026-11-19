import QtQuick
import Quickshell.Services.Kde
import Quickshell.Widgets
import Sedmio.Style

// Яркость экранов, клик — раздел «Яркость» панели управления. Нет
// экранов с настраиваемой яркостью — не видна.
BarButton {
    id: root
    required property string screenName
    visible: ScreenBrightness.displays.length > 0
    active: ShellState.controlShows(screenName, "brightness")
    hint: "Яркость"
    onClicked: { if (tooltip) tooltip.hide(); ShellState.toggleControl(screenName, "brightness"); }

    IconImage {
        anchors.centerIn: parent
        implicitSize: 20
        source: Icons.path("brightness-high")
    }
}
