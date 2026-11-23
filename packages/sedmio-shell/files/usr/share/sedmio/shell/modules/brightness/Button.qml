import QtQuick
import qs
import Quickshell.Services.Kde
import Quickshell.Widgets
import Sedmio.Style

// Яркость экранов, клик — раздел «Яркость» панели управления. Нет
// экранов с настраиваемой яркостью — не видна.
BarButton {
    id: root
    visible: ScreenBrightness.displays.length > 0
    active: ShellState.controlShows(screenName, "brightness")
    hint: "Яркость"
    onClicked: { if (tooltip) tooltip.hide(); ShellState.toggleControl(screenName, "brightness"); }

    SIcon {
        anchors.centerIn: parent
        implicitSize: root.iconSize
        symbolic: true
        color: Theme.ink
        name: ("brightness-high")
    }
}
