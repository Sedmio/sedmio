import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Networking
import Quickshell.Services.Kde
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import Sedmio.Style

// Содержимое панели управления: дата и календарь, плитки (сеть, Bluetooth,
// «Не беспокоить», режим питания), громкость, микрофон, яркость и кнопки
// выключения. Сеть, Bluetooth и звук открывают свои страницы. Подложку
// рисует DrawerShape в слое рамки, здесь только то, что на ней.
Item {
    id: root
    property bool open: false
    property real maxHeight: 700
    signal closeRequested(bool restoreFocus)

    // "main" | "network" | "bluetooth" | "audio"
    property string page: "main"

    readonly property real wantedHeight: Math.min(maxHeight,
        page === "main" ? main.implicitHeight : (pageLoader.item ? pageLoader.item.implicitHeight : 0))

    onOpenChanged: {
        if (!open) return;
        page = "main";
        confirm = "";
        calendar.reset();
        keys.forceActiveFocus();
    }

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
    function profileIcon(p) {
        return p === PowerProfile.PowerSaver ? "battery-profile-powersave"
             : p === PowerProfile.Performance ? "battery-profile-performance"
             : "battery-profile-balanced";
    }

    // ---- Выключение и выход: опасное — по второму нажатию.

    property string confirm: ""
    Timer {
        id: confirmTimer
        interval: 4000
        onTriggered: root.confirm = ""
    }

    readonly property var sessionActions: [
        { id: "lock", icon: "system-lock-screen", hint: "Заблокировать", safe: true,
          command: ["loginctl", "lock-session"] },
        { id: "suspend", icon: "system-suspend", hint: "Сон", safe: true,
          command: ["systemctl", "suspend"] },
        { id: "logout", icon: "system-log-out", hint: "Выйти", ask: "Ещё раз — выйти",
          command: ["busctl", "--user", "call", "org.kde.Shutdown", "/Shutdown", "org.kde.Shutdown", "logout"] },
        { id: "reboot", icon: "system-reboot", hint: "Перезагрузить", ask: "Ещё раз — перезагрузить",
          command: ["busctl", "--user", "call", "org.kde.Shutdown", "/Shutdown", "org.kde.Shutdown", "logoutAndReboot"] },
        { id: "shutdown", icon: "system-shutdown", hint: "Выключить", ask: "Ещё раз — выключить",
          command: ["busctl", "--user", "call", "org.kde.Shutdown", "/Shutdown", "org.kde.Shutdown", "logoutAndShutdown"] },
    ]

    function runSession(action) {
        if (!action.safe && confirm !== action.id) {
            confirm = action.id;
            confirmTimer.restart();
            return;
        }
        confirm = "";
        closeRequested(false);
        Quickshell.execDetached(action.command);
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

    // ---- Главная страница

    ColumnLayout {
        id: main
        anchors { left: parent.left; right: parent.right; top: parent.top }
        visible: root.page === "main"
        spacing: 14

        // Время и дата
        SystemClock { id: clock; precision: SystemClock.Minutes }
        RowLayout {
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
            Layout.fillWidth: true
        }

        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.line }

        // Плитки
        GridLayout {
            id: tiles
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
                onToggled: {
                    const i = root.profiles.indexOf(PowerProfiles.profile);
                    PowerProfiles.profile = root.profiles[(i + 1) % root.profiles.length];
                }
            }
        }

        // Ползунки
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            SliderRow {
                Layout.fillWidth: true
                readonly property bool ready: root.sink !== null && root.sink.audio !== null
                icon: !ready || root.sink.audio.muted ? "audio-volume-muted"
                    : root.sink.audio.volume < 0.34 ? "audio-volume-low"
                    : root.sink.audio.volume < 0.67 ? "audio-volume-medium" : "audio-volume-high"
                value: ready ? Math.min(1, root.sink.audio.volume) : 0
                muted: !ready || root.sink.audio.muted
                hasDetails: true
                onIconClicked: if (ready) root.sink.audio.muted = !root.sink.audio.muted
                onMoved: v => {
                    if (!ready) return;
                    root.sink.audio.volume = v;
                    if (v > 0 && root.sink.audio.muted) root.sink.audio.muted = false;
                }
                onDetails: root.page = "audio"
            }

            SliderRow {
                Layout.fillWidth: true
                readonly property bool ready: root.source !== null && root.source.audio !== null
                visible: ready
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

        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.line }

        // Параметры и выключение. Подтверждение опасного действия — на месте
        // «Параметров», чтобы кнопки под мышью не сдвигались.
        RowLayout {
            Layout.fillWidth: true
            spacing: 4

            SText {
                Layout.fillWidth: true
                Layout.leftMargin: 6
                visible: root.confirm !== ""
                text: (root.sessionActions.find(a => a.id === root.confirm) ?? {}).ask ?? ""
                color: Theme.terracotta
                size: 13
                weight: 600
                elide: Text.ElideRight
            }

            Rectangle {
                visible: root.confirm === ""
                implicitWidth: settingsRow.implicitWidth + 20
                implicitHeight: 38
                radius: 12
                color: settingsArea.containsMouse ? Theme.paperDeep : "transparent"
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

            Item { Layout.fillWidth: true; visible: root.confirm === "" }

            Repeater {
                model: root.sessionActions
                Rectangle {
                    id: action
                    required property var modelData
                    readonly property bool asking: root.confirm === modelData.id
                    implicitWidth: 38
                    implicitHeight: 38
                    radius: 12
                    color: asking ? Theme.terracotta : (actionArea.containsMouse ? Theme.paperDeep : "transparent")
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                    SIcon {
                        anchors.centerIn: parent
                        name: action.modelData.icon
                        light: action.asking
                    }
                    MouseArea {
                        id: actionArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.runSession(action.modelData)
                    }
                    // Подпись над кнопкой при наведении
                    Rectangle {
                        visible: actionArea.containsMouse && !action.asking
                        anchors { bottom: parent.top; bottomMargin: 6; horizontalCenter: parent.horizontalCenter }
                        width: hintText.implicitWidth + 16
                        height: 26
                        radius: 8
                        color: Theme.ink
                        SText {
                            id: hintText
                            anchors.centerIn: parent
                            text: action.modelData.hint
                            size: 12
                            weight: 500
                            color: Theme.textOnGreen
                        }
                    }
                }
            }
        }
    }

    // ---- Страницы

    Loader {
        id: pageLoader
        anchors { left: parent.left; right: parent.right; top: parent.top }
        active: root.page !== "main"
        sourceComponent: root.page === "network" ? networkPage
            : root.page === "bluetooth" ? bluetoothPage
            : root.page === "audio" ? audioPage : null
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
    Component {
        id: audioPage
        AudioPage {
            maxHeight: root.maxHeight
            onBack: { root.page = "main"; keys.forceActiveFocus(); }
            onOpenExternal: command => root.openExternal(command)
        }
    }
}
