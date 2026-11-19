import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Networking
import Quickshell.Services.Kde
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import Sedmio.Style

// Содержимое панели управления. У каждой кнопки панели свой раздел
// (ShellState.controlSection):
//   sound    — громкость, микрофон, куда выводить звук;
//   calendar — дата и календарь;
//   battery  — заряд, режим питания, яркость;
//   settings — плитки (сеть, Bluetooth, «Не беспокоить», режим питания),
//              яркость и «Параметры».
// Сеть и Bluetooth открывают свои страницы. Выключение — в запуске
// программ (SessionButtons). Подложку рисует DrawerShape в слое рамки,
// здесь только то, что на ней.
Item {
    id: root
    property bool open: false
    property string section: "settings"
    property real maxHeight: 700
    signal closeRequested(bool restoreFocus)

    // "main" | "network" | "bluetooth"
    property string page: "main"

    readonly property real wantedHeight: Math.min(maxHeight,
        page === "main" ? main.implicitHeight : (pageLoader.item ? pageLoader.item.implicitHeight : 0))

    function reset() {
        page = "main";
        calendar.reset();
        keys.forceActiveFocus();
    }
    onOpenChanged: if (open) reset()
    // Нажали кнопку другого раздела, не закрывая панель.
    onSectionChanged: if (open) reset()

    // Запустить программу (параметры системы) и закрыть панель.
    function openExternal(command) {
        ShellState.launch("", command);
        closeRequested(false);
    }

    // ---- Состояние

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    PwObjectTracker { objects: [root.sink, root.source] }

    readonly property var netDevices: Networking.devices.values
    // Карта в режиме точки доступа (раздаёт интернет) — не для подключения.
    readonly property var wifi: netDevices.find(d => d.type === DeviceType.Wifi && d.mode !== WifiDeviceMode.AccessPoint) ?? null
    readonly property var wired: netDevices.find(d => d.type === DeviceType.Wired) ?? null
    readonly property var wifiNetwork: wifi ? (wifi.networks.values.find(n => n.connected) ?? null) : null

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property var btConnected: adapter ? adapter.devices.values.filter(d => d.connected) : []

    readonly property var profiles: PowerProfiles.hasPerformanceProfile
        ? [PowerProfile.PowerSaver, PowerProfile.Balanced, PowerProfile.Performance]
        : [PowerProfile.PowerSaver, PowerProfile.Balanced]

    function profileName(p) {
        return p === PowerProfile.PowerSaver ? "Экономия энергии"
             : p === PowerProfile.Performance ? "Производительность" : "Сбалансированный";
    }
    function nextProfile() {
        const i = profiles.indexOf(PowerProfiles.profile);
        PowerProfiles.profile = profiles[(i + 1) % profiles.length];
    }
    function profileIcon(p) {
        return p === PowerProfile.PowerSaver ? "battery-profile-powersave"
             : p === PowerProfile.Performance ? "battery-profile-performance"
             : "battery-profile-balanced";
    }

    // ---- Клавиши: Esc — назад или закрыть.

    Item {
        id: keys
        focus: true
        Keys.onEscapePressed: {
            if (root.page !== "main") root.page = "main";
            else root.closeRequested(true);
        }
    }

    // ---- Главная страница раздела

    readonly property var battery: UPower.displayDevice
    readonly property bool hasBattery: battery !== null && battery.isLaptopBattery && battery.isPresent

    ColumnLayout {
        id: main
        anchors { left: parent.left; right: parent.right; top: parent.top }
        visible: root.page === "main"
        spacing: 14

        // ---- Часы: время, дата, календарь

        SystemClock { id: clock; precision: SystemClock.Minutes }
        RowLayout {
            visible: root.section === "calendar"
            Layout.fillWidth: true
            Layout.leftMargin: 4
            spacing: 12
            SText {
                text: Qt.formatTime(clock.date, "hh:mm")
                size: 30
                weight: 650
                font.features: ({ "tnum": 1 })
            }
            SText {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                text: {
                    const s = clock.date.toLocaleDateString(Qt.locale(), "dddd, d MMMM");
                    return s.charAt(0).toUpperCase() + s.slice(1);
                }
                color: Theme.inkSoft
                elide: Text.ElideRight
            }
        }

        Calendar {
            id: calendar
            visible: root.section === "calendar"
            Layout.fillWidth: true
        }

        // ---- Батарея: заряд

        RowLayout {
            visible: root.section === "battery" && root.hasBattery
            Layout.fillWidth: true
            Layout.leftMargin: 4
            spacing: 12
            readonly property int percent: root.hasBattery
                ? Math.round(root.battery.percentage * (root.battery.percentage <= 1 ? 100 : 1)) : 0
            SText {
                text: parent.percent + "%"
                size: 30
                weight: 650
                font.features: ({ "tnum": 1 })
            }
            SText {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                text: !root.hasBattery ? ""
                    : root.battery.state === UPowerDeviceState.Charging ? "Заряжается"
                    : root.battery.state === UPowerDeviceState.FullyCharged ? "Заряжена"
                    : UPower.onBattery ? "От батареи" : "Подключено к сети"
                color: Theme.inkSoft
                elide: Text.ElideRight
            }
        }

        // ---- Быстрые настройки: плитки

        GridLayout {
            id: tiles
            visible: root.section === "settings"
            Layout.fillWidth: true
            columns: 2
            rowSpacing: 8
            columnSpacing: 8

            QuickTile {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                icon: root.wifi ? (Networking.wifiEnabled ? "network-wireless" : "network-wireless-disconnected")
                    : (root.wired && root.wired.connected ? "network-wired-activated" : "network-disconnect")
                title: root.wifi ? "Wi‑Fi" : "Сеть"
                subtitle: root.wifi
                    ? (!Networking.wifiEnabled ? "Выключен" : root.wifiNetwork ? root.wifiNetwork.name : "Не подключено")
                    : (root.wired && root.wired.connected ? "Подключено" : "Нет подключения")
                active: root.wifi ? Networking.wifiEnabled : (root.wired !== null && root.wired.connected)
                hasDetails: true
                onToggled: {
                    if (root.wifi) Networking.wifiEnabled = !Networking.wifiEnabled;
                    else root.page = "network";
                }
                onDetails: root.page = "network"
            }

            QuickTile {
                visible: root.adapter !== null
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                icon: root.adapter && root.adapter.enabled ? "network-bluetooth-activated" : "network-bluetooth"
                title: "Bluetooth"
                subtitle: !root.adapter || !root.adapter.enabled ? "Выключен"
                    : root.btConnected.length > 0 ? root.btConnected.map(d => d.name).join(", ") : "Включён"
                active: root.adapter !== null && root.adapter.enabled
                hasDetails: true
                onToggled: root.adapter.enabled = !root.adapter.enabled
                onDetails: root.page = "bluetooth"
            }

            QuickTile {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                icon: NotificationState.doNotDisturb ? "notifications-disabled" : "notifications"
                title: "Не беспокоить"
                subtitle: NotificationState.doNotDisturb ? "Только срочные" : "Выключено"
                active: NotificationState.doNotDisturb
                onToggled: NotificationState.setDoNotDisturb(!NotificationState.doNotDisturb)
            }

            QuickTile {
                // Без Bluetooth плиток три — последняя во всю ширину.
                Layout.columnSpan: root.adapter === null ? 2 : 1
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                icon: root.profileIcon(PowerProfiles.profile)
                title: "Режим питания"
                subtitle: root.profileName(PowerProfiles.profile)
                active: PowerProfiles.profile !== PowerProfile.Balanced
                onToggled: root.nextProfile()
            }
        }

        // ---- Батарея: режим питания

        QuickTile {
            visible: root.section === "battery"
            Layout.fillWidth: true
            icon: root.profileIcon(PowerProfiles.profile)
            title: "Режим питания"
            subtitle: root.profileName(PowerProfiles.profile)
            active: PowerProfiles.profile !== PowerProfile.Balanced
            onToggled: root.nextProfile()
        }

        // ---- Ползунки: звук — громкость и микрофон; батарея и быстрые
        // настройки — яркость.

        ColumnLayout {
            visible: root.section !== "calendar"
            Layout.fillWidth: true
            spacing: 2

            SliderRow {
                visible: root.section === "sound"
                Layout.fillWidth: true
                readonly property bool ready: root.sink !== null && root.sink.audio !== null
                icon: !ready || root.sink.audio.muted ? "audio-volume-muted"
                    : root.sink.audio.volume < 0.34 ? "audio-volume-low"
                    : root.sink.audio.volume < 0.67 ? "audio-volume-medium" : "audio-volume-high"
                value: ready ? Math.min(1, root.sink.audio.volume) : 0
                muted: !ready || root.sink.audio.muted
                onIconClicked: if (ready) root.sink.audio.muted = !root.sink.audio.muted
                onMoved: v => {
                    if (!ready) return;
                    root.sink.audio.volume = v;
                    if (v > 0 && root.sink.audio.muted) root.sink.audio.muted = false;
                }
            }

            SliderRow {
                Layout.fillWidth: true
                readonly property bool ready: root.source !== null && root.source.audio !== null
                visible: ready && root.section === "sound"
                icon: ready && root.source.audio.muted ? "microphone-sensitivity-muted" : "audio-input-microphone"
                value: ready ? Math.min(1, root.source.audio.volume) : 0
                muted: !ready || root.source.audio.muted
                onIconClicked: if (ready) root.source.audio.muted = !root.source.audio.muted
                onMoved: v => { if (ready) root.source.audio.volume = v; }
            }

            Repeater {
                // Модель — число экранов, а не сам список: список приходит
                // заново на каждое изменение яркости, и строки пересоздавались
                // бы прямо под пальцем — ползунок нельзя было бы тащить.
                model: ScreenBrightness.displays.length
                SliderRow {
                    required property int index
                    readonly property var modelData: ScreenBrightness.displays[index] ?? ({})
                    visible: root.section === "battery" || root.section === "settings"
                    Layout.fillWidth: true
                    icon: "brightness-high"
                    iconClickable: false
                    label: ScreenBrightness.displays.length > 1 ? modelData.label : ""
                    value: modelData.brightness ?? 0
                    maximum: modelData.maxBrightness ?? 1
                    onMoved: v => ScreenBrightness.setBrightness(modelData.name, Math.round(v))
                }
            }
        }

        // ---- Звук: куда выводить и откуда брать

        Rectangle { visible: root.section === "sound"; Layout.fillWidth: true; implicitHeight: 1; color: Theme.line }

        AudioPage {
            visible: root.section === "sound"
            Layout.fillWidth: true
            showHeader: false
            maxHeight: root.maxHeight - 60
            onOpenExternal: command => root.openExternal(command)
        }

        // ---- Быстрые настройки: «Параметры»

        Rectangle { visible: root.section === "settings"; Layout.fillWidth: true; implicitHeight: 1; color: Theme.line }

        Rectangle {
            visible: root.section === "settings"
            implicitWidth: settingsRow.implicitWidth + 20
            implicitHeight: 38
            radius: 12
            color: settingsArea.containsMouse ? Theme.paperDeep : Qt.alpha(Theme.paperDeep, 0)
            RowLayout {
                id: settingsRow
                anchors.centerIn: parent
                spacing: 8
                SIcon { name: "configure" }
                SText { text: "Параметры"; size: 13; weight: 550 }
            }
            MouseArea {
                id: settingsArea
                anchors.fill: parent
                hoverEnabled: true
                onClicked: root.openExternal(["/usr/lib/sedmio/open-settings"])
            }
        }
    }

    // ---- Страницы

    Loader {
        id: pageLoader
        anchors { left: parent.left; right: parent.right; top: parent.top }
        active: root.page !== "main"
        sourceComponent: root.page === "network" ? networkPage
            : root.page === "bluetooth" ? bluetoothPage : null
    }

    Component {
        id: networkPage
        NetworkPage {
            maxHeight: root.maxHeight
            onBack: { root.page = "main"; keys.forceActiveFocus(); }
            onOpenExternal: command => root.openExternal(command)
        }
    }
    Component {
        id: bluetoothPage
        BluetoothPage {
            maxHeight: root.maxHeight
            onBack: { root.page = "main"; keys.forceActiveFocus(); }
            onOpenExternal: command => root.openExternal(command)
        }
    }
}
