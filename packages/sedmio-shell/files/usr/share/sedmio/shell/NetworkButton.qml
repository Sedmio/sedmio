import QtQuick
import Quickshell.Networking
import Quickshell.Widgets
import Sedmio.Style

// Сеть: значок подключения, клик — раздел «Сеть» панели управления
// (проводное подключение и сети Wi‑Fi).
BarButton {
    id: root
    required property string screenName
    active: ShellState.controlShows(screenName, "network")
    onClicked: { if (tooltip) tooltip.hide(); ShellState.toggleControl(screenName, "network"); }

    readonly property var devices: Networking.devices.values
    // Карта в режиме точки доступа (раздаёт интернет) — не для подключения.
    readonly property var wifi: devices.find(d => d.type === DeviceType.Wifi && d.mode !== WifiDeviceMode.AccessPoint) ?? null
    readonly property var wired: devices.find(d => d.type === DeviceType.Wired) ?? null
    readonly property bool wiredUp: wired !== null && wired.connected
    readonly property var wifiNetwork: wifi && Networking.wifiEnabled ? (wifi.networks.values.find(n => n.connected) ?? null) : null

    hint: wiredUp ? "Сеть: подключено по проводу"
        : wifiNetwork ? "Wi‑Fi: " + wifiNetwork.name
        : wifi && !Networking.wifiEnabled ? "Wi‑Fi выключен"
        : "Нет подключения"

    IconImage {
        anchors.centerIn: parent
        implicitSize: 20
        source: Icons.path(
            root.wiredUp ? "network-wired-activated"
            : root.wifiNetwork ? (root.wifiNetwork.signalStrength > 0.75 ? "network-wireless-signal-excellent"
                : root.wifiNetwork.signalStrength > 0.5 ? "network-wireless-signal-good"
                : root.wifiNetwork.signalStrength > 0.25 ? "network-wireless-signal-ok"
                : "network-wireless-signal-weak")
            : root.wifi && !Networking.wifiEnabled ? "network-wireless-disconnected"
            : "network-disconnect")
    }
}
