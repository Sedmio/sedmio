import QtQuick
import org.kde.bluezqt as BluezQt

// «Bluetooth»: включить, как компьютер называется и виден ли он другим,
// свои устройства (подключить, отключить, забыть) и новые рядом. Всё через
// BlueZ (BluezQt). Код сопряжения, если нужен, спрашивает оболочка — её
// агент BlueZ.
Page {
    id: root
    title: "Bluetooth"

    readonly property var manager: BluezQt.Manager
    // Первый адаптер (hci0), включён он или нет: с двумя адаптерами
    // раздел не должен перескакивать на другой, когда этот выключили.
    readonly property var adapter: {
        revision;
        if (!manager.operational) return null; // служба Bluetooth остановлена
        const list = manager.adapters;
        let first = null;
        for (let i = 0; i < list.length; i++)
            if (!first || list[i].ubi < first.ubi) first = list[i];
        return first;
    }
    readonly property bool on: adapter !== null && adapter.powered && !manager.bluetoothBlocked
    // adapter.devices — живой список, а devicesChanged BluezQt шлёт раньше,
    // чем устройство в нём появится: пересчитываем чуть позже, по ревизии.
    property int revision: 0
    function refresh() { Qt.callLater(() => root.revision++); }
    readonly property var devices: {
        revision;
        const list = adapter ? adapter.devices : [];
        const copy = [];
        for (let i = 0; i < list.length; i++) copy.push(list[i]);
        return copy;
    }
    Connections {
        target: root.manager
        function onInitFinished() { root.refresh(); }
        function onOperationalChanged() { root.refresh(); }
        function onAdapterAdded() { root.refresh(); }
        function onAdapterRemoved() { root.refresh(); }
        function onUsableAdapterChanged() { root.refresh(); }
        function onDeviceAdded() { root.refresh(); }
        function onDeviceRemoved() { root.refresh(); }
    }
    Connections {
        target: root.adapter
        function onDevicesChanged() { root.refresh(); }
        function onDeviceFound() { root.refresh(); }
        function onDeviceRemoved() { root.refresh(); }
        function onDeviceChanged() { root.refresh(); }
    }
    readonly property var paired: devices.filter(d => d.paired)
        .sort((a, b) => (b.connected - a.connected) || a.name.localeCompare(b.name))
    // Без имени (только адрес) — не показываем: такое всё равно не узнать.
    readonly property var found: devices.filter(d => !d.paired && d.remoteName !== "")
        .sort((a, b) => b.rssi - a.rssi)


    // Включить попросили, когда адаптер был заблокирован (rfkill) и пропал:
    // включим, как только появится.
    property bool wantOn: false
    property string pairing        // адрес, который сейчас сопрягаем
    property string working        // адрес, который подключаем или отключаем
    property string workingText
    property string confirmForget  // адрес, для которого спрошено «Забыть?»
    property string message
    property bool messageIsError: false

    onAdapterChanged: {
        // Пропал или сменился адаптер — незаконченное забываем.
        pairing = "";
        working = "";
        confirmForget = "";
        if (wantOn && adapter) {
            wantOn = false;
            adapter.powered = true;
        }
        if (scanning) adapter.startDiscovery();
    }

    // Пока раздел открыт и Bluetooth включён — ищем устройства рядом.
    readonly property bool scanning: on && visible
    onScanningChanged: {
        if (!adapter) return;
        if (scanning) adapter.startDiscovery();
        else if (adapter.discovering) adapter.stopDiscovery();
    }
    Component.onCompleted: if (scanning) adapter.startDiscovery()
    Component.onDestruction: if (adapter && adapter.discovering) adapter.stopDiscovery()

    function setOn(value) {
        message = "";
        if (!value) {
            if (adapter) adapter.powered = false;
            return;
        }
        if (manager.bluetoothBlocked) {
            wantOn = true;
            manager.bluetoothBlocked = false;
        }
        if (adapter) adapter.powered = true;
    }

    // call — PendingCall BlueZ; ok() — если без ошибки; always() — в любом случае.
    function watch(call, failure, ok, always) {
        if (!call) {
            if (always) always();
            return;
        }
        call.finished.connect(() => {
            if (call.error) {
                const reason = root.explain(call.errorText);
                if (reason !== null) {
                    root.message = failure + (reason ? ": " + reason : "");
                    root.messageIsError = true;
                }
            } else if (ok) {
                ok();
            }
            if (always) always();
        });
    }

    // Ошибка BlueZ → по-русски; null — сообщать нечего (отменили сами).
    function explain(text) {
        const t = String(text || "");
        if (/cancel/i.test(t)) return null;
        if (/rejected|failed.*auth|authentication failed/i.test(t)) return "устройство отклонило сопряжение";
        if (/timeout|timed out|page-timeout|host is down/i.test(t)) return "устройство не отвечает — оно включено и рядом?";
        if (/profile-unavailable|not supported|refused/i.test(t)) return "устройство не поддерживает подключение к компьютеру";
        if (/in progress/i.test(t)) return "уже выполняется, подождите";
        if (/not ready|not powered/i.test(t)) return "Bluetooth ещё не готов";
        return t;
    }

    function connectDevice(device) {
        message = "";
        working = device.address;
        workingText = "Подключение…";
        watch(device.connectToDevice(), "Не удалось подключить «" + device.name + "»", null, () => root.working = "");
    }

    function disconnectDevice(device) {
        message = "";
        working = device.address;
        workingText = "Отключение…";
        watch(device.disconnectFromDevice(), "Не удалось отключить «" + device.name + "»", null, () => root.working = "");
    }

    function addDevice(device) {
        message = "";
        pairing = device.address;
        watch(device.pair(), "Не удалось добавить «" + device.name + "»", () => {
            // Своё устройство — доверенное: подключается само, без вопросов.
            device.trusted = true;
            root.connectDevice(device);
        }, () => root.pairing = "");
    }

    function forget(device) {
        message = "";
        confirmForget = "";
        watch(adapter.removeDevice(device), "Не удалось забыть «" + device.name + "»");
    }

    function status(device) {
        if (root.pairing === device.address) return "Добавляется…";
        if (root.working === device.address) return root.workingText;
        if (!device.connected) return device.paired ? "Не подключено" : "";
        const battery = device.battery ? device.battery.percentage : -1;
        return battery >= 0 ? "Подключено · заряд " + battery + "%" : "Подключено";
    }

    Timer {
        // «Забыть?» ждёт подтверждения недолго.
        running: root.confirmForget !== ""
        interval: 6000
        onTriggered: root.confirmForget = ""
    }

    SText {
        width: parent.width
        visible: root.adapter === null && !root.manager.bluetoothBlocked
        text: root.manager.operational ? "Адаптер Bluetooth не найден."
                                       : "Адаптер Bluetooth не найден или служба Bluetooth не запущена."
        color: Theme.inkMuted
        wrapMode: Text.Wrap
    }

    Card {
        visible: root.adapter !== null || root.manager.bluetoothBlocked
        Setting {
            label: "Bluetooth"
            hint: root.on ? "Включён" : "Выключен"
            last: !root.on
            SSwitch {
                checked: root.on
                onToggled: root.setOn(!checked)
            }
        }
        Setting {
            visible: root.on
            label: "Имя компьютера"
            hint: "Так его видят телефон и другие устройства"
            Row {
                spacing: 8
                SField {
                    id: nameField
                    width: 220
                    text: root.adapter ? root.adapter.name : ""
                    maximumLength: 248
                    onAccepted: if (text.trim() !== "") root.adapter.name = text.trim()
                }
                SButton {
                    text: "Сохранить"
                    primary: true
                    visible: root.adapter !== null && nameField.text.trim() !== "" && nameField.text.trim() !== root.adapter.name
                    onClicked: root.adapter.name = nameField.text.trim()
                }
            }
        }
        Setting {
            visible: root.on
            last: true
            label: "Виден другим устройствам"
            hint: root.adapter && root.adapter.discoverable && root.adapter.discoverableTimeout > 0
                  ? "Сам перестанет через " + Math.round(root.adapter.discoverableTimeout / 60) + " мин."
                  : "Включите, чтобы найти компьютер с телефона"
            SSwitch {
                checked: root.adapter !== null && root.adapter.discoverable
                onToggled: root.adapter.discoverable = !checked
            }
        }
    }

    SText {
        width: parent.width
        visible: root.message !== ""
        text: root.message
        color: root.messageIsError ? Theme.terracotta : Theme.green
        wrapMode: Text.Wrap
    }

    Card {
        title: "Мои устройства"
        visible: root.on && root.paired.length > 0
        Repeater {
            model: root.paired
            DeviceRow {
                required property var modelData
                required property int index
                device: modelData
                last: index === root.paired.length - 1
                SButton {
                    text: root.confirmForget === modelData.address ? "Точно забыть?" : "Забыть"
                    danger: root.confirmForget === modelData.address
                    onClicked: {
                        if (root.confirmForget === modelData.address) root.forget(modelData);
                        else root.confirmForget = modelData.address;
                    }
                }
                SButton {
                    text: modelData.connected ? "Отключить" : "Подключить"
                    primary: !modelData.connected
                    enabled: root.working !== modelData.address
                    opacity: enabled ? 1 : 0.5
                    onClicked: modelData.connected ? root.disconnectDevice(modelData) : root.connectDevice(modelData)
                }
            }
        }
    }

    Card {
        title: "Добавить устройство"
        visible: root.on
        SText {
            width: parent.width
            visible: root.found.length === 0
            padding: 16
            text: "Ищем устройства рядом… Включите на устройстве режим сопряжения."
            color: Theme.inkMuted
            wrapMode: Text.Wrap
        }
        Repeater {
            model: root.found
            DeviceRow {
                required property var modelData
                required property int index
                device: modelData
                last: index === root.found.length - 1
                SButton {
                    text: "Добавить"
                    primary: true
                    visible: root.pairing !== modelData.address
                    enabled: root.pairing === ""
                    onClicked: root.addDevice(modelData)
                }
            }
        }
    }

    // Строка устройства: значок, имя, состояние, кнопки справа.
    component DeviceRow: Item {
        id: row
        property var device
        property bool last: false
        default property alias buttons: buttonRow.data

        width: parent ? parent.width : 0
        implicitHeight: Math.max(texts.height, buttonRow.height) + 24

        SIcon {
            id: icon
            anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
            size: 24
            name: row.device && row.device.icon !== "" ? row.device.icon : "preferences-system-bluetooth"
        }
        Column {
            id: texts
            anchors { left: icon.right; leftMargin: 12; right: buttonRow.left; rightMargin: 16; verticalCenter: parent.verticalCenter }
            spacing: 2
            SText {
                width: parent.width
                text: row.device ? row.device.name : ""
                elide: Text.ElideRight
            }
            SText {
                width: parent.width
                visible: text !== ""
                text: row.device ? root.status(row.device) : ""
                size: Theme.fontSmall
                color: Theme.inkMuted
            }
        }
        Row {
            id: buttonRow
            anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
            spacing: 8
        }
        Rectangle {
            visible: !row.last
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 16; rightMargin: 16 }
            height: 1
            color: Theme.line
        }
    }
}
