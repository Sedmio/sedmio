import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Networking

// Страница «Сеть»: проводное подключение и сети Wi‑Fi. Клик по сети —
// подключиться; к новой защищённой сети пароль вводится прямо в строке.
ColumnLayout {
    id: page
    property real maxHeight: 600
    signal back()
    signal openExternal(var command)

    readonly property var devices: Networking.devices.values
    readonly property var wifi: devices.find(d => d.type === DeviceType.Wifi && d.mode !== WifiDeviceMode.AccessPoint) ?? null
    readonly property var wired: devices.find(d => d.type === DeviceType.Wired) ?? null

    // Видимые сети: подключённая, потом знакомые, потом по силе сигнала.
    readonly property var networks: {
        if (!wifi || !Networking.wifiEnabled) return [];
        return wifi.networks.values
            .filter(n => n.name !== "")
            .sort((a, b) => (b.connected - a.connected) || (b.known - a.known)
                || (b.signalStrength - a.signalStrength));
    }

    // Раскрытая строка (имя сети) и ошибка в ней.
    property string expanded: ""
    property string error: ""

    spacing: 10

    // Пока страница открыта, Wi‑Fi ищет сети.
    Component.onCompleted: if (wifi) wifi.scannerEnabled = true
    Component.onDestruction: if (wifi) wifi.scannerEnabled = false

    function needsPassword(network) {
        return network.security !== WifiSecurityType.Open && network.security !== WifiSecurityType.Owe;
    }

    function signalIcon(strength) {
        return strength > 0.75 ? "network-wireless-signal-excellent"
             : strength > 0.5 ? "network-wireless-signal-good"
             : strength > 0.25 ? "network-wireless-signal-ok"
             : "network-wireless-signal-weak";
    }

    function stateText(network) {
        switch (network.state) {
        case ConnectionState.Connected: return "Подключено";
        case ConnectionState.Connecting: return "Подключение…";
        case ConnectionState.Disconnecting: return "Отключение…";
        }
        return network.known ? "Сохранена" : (needsPassword(network) ? "Защищена" : "Открытая");
    }

    function activate(network) {
        error = "";
        if (network.connected) {
            expanded = expanded === network.name ? "" : network.name;
        } else if (network.known || !needsPassword(network)) {
            expanded = "";
            network.connect();
        } else {
            expanded = network.name;
        }
    }

    PageHeader {
        Layout.fillWidth: true
        title: page.wifi ? "Wi‑Fi" : "Сеть"
        showSwitch: page.wifi !== null
        checked: Networking.wifiEnabled
        onBack: page.back()
        onToggled: Networking.wifiEnabled = !Networking.wifiEnabled
    }

    ListRow {
        Layout.fillWidth: true
        visible: page.wired !== null
        icon: page.wired && page.wired.connected ? "network-wired-activated" : "network-wired"
        title: "Кабель"
        subtitle: !page.wired ? "" : page.wired.connected ? "Подключено" : "Не подключено"
        selected: page.wired !== null && page.wired.connected
    }

    SText {
        Layout.fillWidth: true
        Layout.leftMargin: 12
        visible: text !== ""
        text: page.wifi === null ? (page.wired ? "" : "Сетевых устройств нет")
            : page.networks.length > 0 ? ""
            : !Networking.wifiEnabled ? "Wi‑Fi выключен"
            : "Ищем сети…"
        color: Theme.inkMuted
        size: 13
    }

    ListView {
        id: list
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(contentHeight, Math.max(160, page.maxHeight - 160))
        visible: page.networks.length > 0
        clip: true
        spacing: 2
        boundsBehavior: Flickable.StopAtBounds

        model: ScriptModel { values: page.networks }

        delegate: ListRow {
            id: row
            required property var modelData
            readonly property bool open: page.expanded === modelData.name
            width: list.width
            icon: page.signalIcon(modelData.signalStrength)
            title: modelData.name
            subtitle: page.stateText(modelData)
            trailingIcon: page.needsPassword(modelData) ? "object-locked" : ""
            selected: modelData.connected
            onClicked: page.activate(modelData)

            Connections {
                target: row.modelData
                function onConnectionFailed(reason) {
                    page.expanded = row.modelData.name;
                    page.error = reason === ConnectionFailReason.NoSecrets
                        ? "Неверный пароль" : "Не удалось подключиться";
                }
            }

            // Подключённая: отключить или забыть
            RowLayout {
                visible: row.open && row.modelData.connected
                Layout.fillWidth: true
                spacing: 6
                SButton { text: "Отключить"; onClicked: { row.modelData.disconnect(); page.expanded = ""; } }
                SButton { text: "Забыть"; onClicked: { row.modelData.forget(); page.expanded = ""; } }
                Item { Layout.fillWidth: true }
            }

            // Новая защищённая сеть: пароль
            ColumnLayout {
                visible: row.open && !row.modelData.connected
                Layout.fillWidth: true
                spacing: 6

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 38
                    radius: 10
                    color: Theme.surface
                    border.width: 1
                    border.color: password.activeFocus ? Theme.lineStrong : Theme.line

                    TextInput {
                        id: password
                        anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                        verticalAlignment: TextInput.AlignVCenter
                        echoMode: TextInput.Password
                        passwordCharacter: "•"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontBody
                        color: Theme.ink
                        clip: true
                        onVisibleChanged: if (visible) { text = ""; forceActiveFocus(); }
                        Keys.onReturnPressed: connectButton.clicked()
                        Keys.onEnterPressed: connectButton.clicked()
                        Keys.onEscapePressed: page.expanded = ""

                        SText {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: password.text === ""
                            text: "Пароль"
                            color: Theme.inkMuted
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    SText {
                        Layout.fillWidth: true
                        text: page.error
                        color: Theme.terracotta
                        size: 13
                    }
                    SButton {
                        id: connectButton
                        text: "Подключиться"
                        primary: true
                        onClicked: {
                            if (password.text.length < 8) {
                                page.error = "Пароль не короче 8 символов";
                                return;
                            }
                            page.error = "";
                            row.modelData.connectWithPsk(password.text);
                            page.expanded = "";
                        }
                    }
                }
            }
        }
    }

    ListRow {
        Layout.fillWidth: true
        icon: "configure"
        title: "Параметры сети"
        onClicked: page.openExternal(["systemsettings", "kcm_networkmanagement"])
    }
}
