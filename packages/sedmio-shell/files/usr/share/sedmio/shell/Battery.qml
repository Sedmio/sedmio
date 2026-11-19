import QtQuick
import Quickshell
import Quickshell.Services.UPower
import Quickshell.Widgets
import Sedmio.Style

// Батарея ноутбука (UPower), клик — заряд, режим питания и яркость.
// На компьютере без батареи не видна.
BarButton {
    id: root
    required property string screenName
    active: ShellState.controlShows(screenName, "battery")
    onClicked: { if (tooltip) tooltip.hide(); ShellState.toggleControl(screenName, "battery"); }
    readonly property var device: UPower.displayDevice
    readonly property bool present: device !== null && device.isLaptopBattery && device.isPresent
    // UPower отдаёт долю от 0 до 1
    readonly property int percent: present ? Math.round(device.percentage * (device.percentage <= 1 ? 100 : 1)) : 0
    readonly property bool charging: present && device.state === UPowerDeviceState.Charging
    readonly property bool full: present && device.state === UPowerDeviceState.FullyCharged

    visible: present
    hint: !present ? "" : "Батарея " + percent + "%"
        + (charging ? ", заряжается" : full ? ", заряжена" : UPower.onBattery ? ", от батареи" : "")

    IconImage {
        anchors.centerIn: parent
        implicitSize: 20
        source: Icons.path(root.device ? root.device.iconName : "", "battery-missing")
    }

    // Мало заряда — подсветить
    Rectangle {
        visible: root.present && !root.charging && root.percent <= 15
        anchors { right: parent.right; top: parent.top; margins: 5 }
        width: 6; height: 6; radius: 3
        color: Theme.terracotta
    }
}
