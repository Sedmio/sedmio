import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Services.Kde
import Quickshell.Wayland
import Sedmio.Style

// Сопряжение Bluetooth: сверить код, ввести код с устройства, набрать код
// на клавиатуре устройства или разрешить подключение. Вместо окон bluedevil.
ModalWindow {
    id: root
    required property BluetoothAgent agent

    readonly property string kind: agent.kind
    readonly property bool display: kind === "display-passkey" || kind === "display-pin"
    readonly property bool asking: kind === "passkey" || kind === "pin"
    readonly property var device: Bluetooth.devices.values.find(d => d.dbusPath === agent.devicePath) ?? null

    active: agent.active
    WlrLayershell.namespace: "sedmio-bluetooth"
    iconName: agent.deviceIcon !== "" ? agent.deviceIcon : "network-bluetooth"
    title: kind === "authorize" || kind === "service" ? "Разрешить подключение?" : "Сопряжение Bluetooth"
    subtitle: agent.deviceName !== "" ? "«" + agent.deviceName + "»" : ""

    // Что просит устройство (AuthorizeService) — по UUID службы.
    function serviceName(uuid) {
        const short = uuid.toLowerCase().substring(4, 8);
        switch (short) {
        case "110a": case "110b": case "110d": return "передавать звук";
        case "110c": case "110e": case "110f": return "управлять воспроизведением";
        case "1108": case "1112": case "111e": case "111f": return "звонки через гарнитуру";
        case "1105": case "1106": return "передавать файлы";
        case "1124": return "работать как клавиатура или мышь";
        case "1115": case "1116": return "подключаться к сети";
        default: return "пользоваться службой " + uuid;
        }
    }

    // «123456» → «123 456»
    function spaced(code) {
        return code.length === 6 ? code.substring(0, 3) + " " + code.substring(3) : code;
    }

    function confirm() {
        if (asking) {
            const text = input.text.trim();
            if (text === "" || (kind === "passkey" && !/^\d{1,6}$/.test(text))) {
                shake();
                return;
            }
            agent.accept(text);
        } else {
            agent.accept();
        }
    }

    function cancel() {
        // Код набирают на устройстве — BlueZ ответа не ждёт, отменяем само сопряжение.
        if (display && device && device.pairing) device.cancelPair();
        agent.reject();
    }

    onActiveChanged: {
        if (!active) return;
        input.clear();
        if (asking) input.focusInput();
        else keys.forceActiveFocus();
    }

    Connections {
        target: root.agent
        function onRequestChanged() {
            if (!root.agent.active) return;
            input.clear();
            if (root.asking) input.focusInput();
            else keys.forceActiveFocus();
        }
    }

    // Код набран на устройстве (или сопряжение сорвалось) — показывать больше нечего.
    Connections {
        target: root.display ? root.device : null
        function onPairingChanged() {
            if (!root.device.pairing) root.agent.accept();
        }
        function onPairedChanged() {
            if (root.device.paired) root.agent.accept();
        }
    }

    Item {
        id: keys
        Keys.onEscapePressed: root.cancel()
        Keys.onReturnPressed: if (!root.display) root.confirm()
        Keys.onEnterPressed: if (!root.display) root.confirm()
    }

    SText {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        color: Theme.inkSoft
        text: {
            switch (root.kind) {
            case "confirm": return "Проверьте, что на устройстве показан такой же код.";
            case "passkey": case "pin": return "Введите код, который показан на устройстве.";
            case "display-passkey": case "display-pin":
                return "Наберите этот код на клавиатуре устройства и нажмите Enter.";
            case "authorize": return "Устройство хочет подключиться к компьютеру.";
            case "service": return "Устройство хочет " + root.serviceName(root.agent.service) + ".";
            default: return "";
            }
        }
    }

    // Код крупно: сверить или набрать на устройстве. Набранные цифры — зелёные.
    Row {
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: 4
        Layout.bottomMargin: 4
        visible: root.kind === "confirm" || root.display
        spacing: 2

        Repeater {
            model: root.spaced(root.agent.code).split("")
            SText {
                required property string modelData
                required property int index
                // Позиция цифры без пробела
                readonly property int digit: index > 3 ? index - 1 : index
                text: modelData
                size: 34
                weight: 650
                font.features: ({ "tnum": 1 })
                color: root.kind === "display-passkey" && modelData !== " " && digit < root.agent.entered
                    ? Theme.green : Theme.ink
            }
        }
    }

    PasswordField {
        id: input
        Layout.fillWidth: true
        visible: root.asking
        reveal: true
        allowReveal: false
        placeholder: root.kind === "passkey" ? "Шесть цифр" : "Код"
        onAccepted: root.confirm()
        onEscapePressed: root.cancel()
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 4
        spacing: 8
        Item { Layout.fillWidth: true }
        SButton {
            text: root.kind === "authorize" || root.kind === "service" ? "Запретить" : "Отмена"
            onClicked: root.cancel()
        }
        SButton {
            visible: !root.display
            primary: true
            text: root.kind === "confirm" ? "Коды совпадают"
                : root.kind === "authorize" || root.kind === "service" ? "Разрешить" : "Подключить"
            onClicked: root.confirm()
        }
    }
}
