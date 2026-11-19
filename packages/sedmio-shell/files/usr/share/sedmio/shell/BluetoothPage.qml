import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth

// Страница «Bluetooth»: свои устройства (подключить/отключить) и найденные
// рядом (клик — сопрячь и подключить). Пока открыта, адаптер ищет устройства.
ColumnLayout {
    id: page
    property real maxHeight: 600
    signal back()
    signal openExternal(var command)

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool enabled: adapter !== null && adapter.enabled
    readonly property var all: adapter ? adapter.devices.values : []
    readonly property var paired: all.filter(d => d.paired || d.bonded)
        .sort((a, b) => (b.connected - a.connected) || a.name.localeCompare(b.name))
    // Безымянные (только адрес) не показываем — их всё равно не узнать.
    readonly property var found: all.filter(d => !d.paired && !d.bonded && d.deviceName !== "")

    spacing: 10

    Component.onCompleted: if (enabled) adapter.discovering = true
    Component.onDestruction: if (adapter && adapter.discovering) adapter.discovering = false
    onEnabledChanged: if (enabled) adapter.discovering = true

    function stateText(device) {
        switch (device.state) {
        case BluetoothDeviceState.Connecting: return "Подключение…";
        case BluetoothDeviceState.Disconnecting: return "Отключение…";
        }
        if (device.pairing) return "Сопряжение…";
        if (!device.connected) return device.paired ? "Не подключено" : "";
        return device.batteryAvailable ? "Подключено · " + Math.round(device.battery * 100) + "%" : "Подключено";
    }

    function deviceIcon(device) {
        return device.icon !== "" ? device.icon : "preferences-system-bluetooth";
    }

    PageHeader {
        Layout.fillWidth: true
        title: "Bluetooth"
        showSwitch: page.adapter !== null
        checked: page.enabled
        onBack: page.back()
        onToggled: page.adapter.enabled = !page.adapter.enabled
    }

    SText {
        Layout.fillWidth: true
        Layout.leftMargin: 12
        visible: !page.enabled
        text: page.adapter === null ? "Адаптера Bluetooth нет" : "Bluetooth выключен"
        color: Theme.inkMuted
        size: 13
    }

    Flickable {
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(contentHeight, Math.max(160, page.maxHeight - 160))
        visible: page.enabled
        contentHeight: lists.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: lists
            width: parent.width
            spacing: 2

            SText {
                Layout.leftMargin: 12
                Layout.topMargin: 4
                visible: page.paired.length > 0
                text: "Мои устройства"
                size: Theme.fontSmall
                weight: 600
                color: Theme.inkMuted
            }

            Repeater {
                model: ScriptModel { values: page.paired }
                ListRow {
                    required property var modelData
                    Layout.fillWidth: true
                    icon: page.deviceIcon(modelData)
                    title: modelData.name
                    subtitle: page.stateText(modelData)
                    selected: modelData.connected
                    onClicked: modelData.connected ? modelData.disconnect() : modelData.connect()
                }
            }

            SText {
                Layout.leftMargin: 12
                Layout.topMargin: 8
                text: page.found.length > 0 ? "Рядом" : "Ищем устройства рядом…"
                size: Theme.fontSmall
                weight: 600
                color: Theme.inkMuted
            }

            Repeater {
                model: ScriptModel { values: page.found }
                ListRow {
                    id: foundRow
                    required property var modelData
                    Layout.fillWidth: true
                    icon: page.deviceIcon(modelData)
                    title: modelData.name
                    subtitle: page.stateText(modelData)
                    onClicked: if (!modelData.pairing) ShellState.pairAndConnect(modelData)
                }
            }
        }
    }

    ListRow {
        Layout.fillWidth: true
        icon: "configure"
        title: "Параметры Bluetooth"
        onClicked: page.openExternal(["/usr/lib/sedmio/open-settings", "bluetooth", "kcm_bluetooth"])
    }
}
