import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Kde
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import Sedmio.Style

// Содержимое панели управления. У каждой кнопки панели свой раздел
// (ShellState.controlSection):
//   network    — проводное подключение и сети Wi‑Fi (NetworkPage);
//   brightness — яркость экранов;
//   sound      — громкость, микрофон, куда выводить звук;
//   calendar   — дата и календарь;
//   battery    — заряд и режим питания;
//   bluetooth  — устройства Bluetooth (BluetoothPage; из плитки в Пуске).
// Плитки «Не беспокоить» и режим питания, «Параметры» и выключение — в
// Пуске (Launcher). Подложку рисует DrawerShape в слое рамки, здесь
// только то, что на ней.
Item {
    id: root
    property bool open: false
    property string section: "calendar"
    property real maxHeight: 700
    signal closeRequested(bool restoreFocus)

    // "main" | "network" | "bluetooth": в разделах сети и Bluetooth —
    // сразу их страница.
    property string page: "main"

    readonly property real wantedHeight: Math.min(maxHeight,
        page === "main" ? main.implicitHeight : (pageLoader.item ? pageLoader.item.implicitHeight : 0))

    function reset() {
        page = section === "network" || section === "bluetooth" ? section : "main";
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

    // ---- Клавиши: Esc — назад или закрыть.

    Item {
        id: keys
        focus: true
        Keys.onEscapePressed: {
            if (root.page !== root.section && root.page !== "main") root.page = "main";
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

        // ---- Батарея: режим питания

        PowerModeTile {
            visible: root.section === "battery"
            Layout.fillWidth: true
        }

        // ---- Ползунки: звук — громкость и микрофон; яркость.

        ColumnLayout {
            visible: root.section === "sound" || root.section === "brightness"
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
                    visible: root.section === "brightness"
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
            showBack: root.section !== "network"
            onBack: { root.page = "main"; keys.forceActiveFocus(); }
            onOpenExternal: command => root.openExternal(command)
        }
    }
    Component {
        id: bluetoothPage
        BluetoothPage {
            maxHeight: root.maxHeight
            showBack: root.section !== "bluetooth"
            onBack: { root.page = "main"; keys.forceActiveFocus(); }
            onOpenExternal: command => root.openExternal(command)
        }
    }
}
