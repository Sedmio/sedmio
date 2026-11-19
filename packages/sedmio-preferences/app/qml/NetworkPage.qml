import QtQuick
import QtQuick.Dialogs
import QtCore
import Sedmio.Style

// «Сеть»: что подключено сейчас и с какими адресами; сохранённые сети —
// подключаться ли самой, лимитная ли, пароль, свой IP-адрес и DNS, забыть;
// скрытая сеть Wi‑Fi и VPN из файла. Сети рядом и подключение к новой —
// в панели оболочки.
Page {
    id: root
    title: "Сеть"

    Network { id: net }

    // Раскрытая сеть (uuid) и черновик её настроек.
    property string editing
    property bool draftManual
    property string draftAddress
    property string draftMask
    property string draftGateway
    property bool draftDnsManual
    property string draftDns
    property string draftError
    // «Сохранено» — ненадолго, на месте ошибки.
    property string draftNote
    Timer {
        running: root.draftNote !== ""
        interval: 3000
        onTriggered: root.draftNote = ""
    }
    // Пароль: показан ли и что в поле.
    property bool passwordShown
    property string passwordText
    property string passwordLoaded
    property string confirmForget
    // После сохранения адресов подключённую сеть переподключаем — иначе
    // новые адреса заработают только при следующем подключении.
    property string reapply
    property bool hiddenOpen: false
    // Раскрытые «Подробнее» у устройств (uni → true).
    property var detailsOpen: ({})

    readonly property var editingConnection: net.connections.find(c => c.uuid === editing) ?? null
    readonly property bool draftDirty: editingConnection !== null
        && (draftManual !== editingConnection.ipManual
            || (draftManual && (draftAddress !== editingConnection.address || draftMask !== editingConnection.prefix
                                || draftGateway !== editingConnection.gateway))
            || draftDnsManual !== editingConnection.dnsManual
            || (draftDnsManual && draftDns !== editingConnection.dns))

    function edit(connection) {
        if (editing === connection.uuid) {
            editing = "";
            return;
        }
        editing = connection.uuid;
        // Адрес пока выдаёт роутер — в «Вручную» подставим нынешний:
        // обычно его и хотят закрепить.
        const now = connection.current || {};
        draftManual = connection.ipManual;
        draftAddress = connection.ipManual ? connection.address : (now.address || "");
        draftMask = connection.ipManual ? connection.prefix : (now.prefix || "255.255.255.0");
        draftGateway = connection.ipManual ? connection.gateway : (now.gateway || "");
        draftDnsManual = connection.dnsManual;
        draftDns = connection.dnsManual ? connection.dns : "";
        draftError = "";
        passwordShown = false;
        passwordText = "";
        passwordLoaded = "";
        confirmForget = "";
    }

    function saveAddressing() {
        const error = net.saveAddressing(editing, draftManual, draftAddress, draftMask, draftGateway, draftDnsManual, draftDns);
        draftError = error;
        if (error === "" && editingConnection && editingConnection.active) reapply = editing;
    }

    Connections {
        target: net
        function onPasswordReady(uuid, password, error) {
            if (uuid !== root.editing) return;
            if (error !== "") {
                root.draftError = "Пароль не показать: " + error;
                return;
            }
            root.passwordLoaded = password;
            root.passwordText = password;
            root.passwordShown = true;
        }
        function onSaved(uuid, error) {
            if (uuid === root.editing) {
                root.draftError = error;
                root.draftNote = error === "" ? "Сохранено" : "";
            }
            if (uuid === root.reapply) {
                root.reapply = "";
                if (error === "") net.reapply(uuid);
            }
            if (error === "" && uuid === root.editing) root.passwordLoaded = root.passwordText;
        }
    }

    Timer {
        // «Забыть?» ждёт подтверждения недолго.
        running: root.confirmForget !== ""
        interval: 6000
        onTriggered: root.confirmForget = ""
    }

    // Сеть забыли (здесь или в панели) — редактор закрыть.
    onEditingConnectionChanged: if (editing !== "" && editingConnection === null) editing = ""

    SText {
        width: parent.width
        visible: !net.available
        text: "Служба сети (NetworkManager) не запущена — подключения не видны и не меняются."
        color: Theme.terracotta
        wrapMode: Text.Wrap
    }

    Card {
        visible: net.available
        SText {
            width: parent.width
            visible: net.devices.length === 0
            padding: 16
            text: "Сетевых устройств нет."
            color: Theme.inkMuted
        }
        Repeater {
            model: net.deviceModel
            Item {
                id: device
                required property var entry
                required property int index
                readonly property bool open: root.detailsOpen[entry.uni] === true
                width: parent.width
                implicitHeight: head.height + (open ? grid.height + 12 : 0)

                Item {
                    id: head
                    width: parent.width
                    height: Math.max(texts.height, buttons.height) + 24
                    SIcon {
                        id: icon
                        anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
                        size: 24
                        name: device.entry.kind === "wifi"
                              ? (device.entry.state === "connected" ? "network-wireless-signal-excellent" : "network-wireless-disconnected")
                              : (device.entry.state === "connected" ? "network-wired-activated" : "network-wired-disconnected")
                    }
                    Column {
                        id: texts
                        anchors { left: icon.right; leftMargin: 12; right: buttons.left; rightMargin: 16; verticalCenter: parent.verticalCenter }
                        spacing: 2
                        SText { text: device.entry.title }
                        SText {
                            width: parent.width
                            text: device.entry.kind === "wifi" && net.wifiHardwareBlocked
                                  ? "Выключен кнопкой или переключателем на корпусе" : device.entry.status
                            size: Theme.fontSmall
                            color: Theme.inkMuted
                            wrapMode: Text.Wrap
                        }
                    }
                    Row {
                        id: buttons
                        anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                        spacing: 12
                        SButton {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: device.entry.details.length > 0
                            text: device.open ? "Скрыть" : "Подробнее"
                            onClicked: {
                                const copy = Object.assign({}, root.detailsOpen);
                                copy[device.entry.uni] = !device.open;
                                root.detailsOpen = copy;
                            }
                        }
                        SSwitch {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: device.entry.kind === "wifi"
                            checked: net.wifiEnabled
                            onToggled: net.setWifiEnabled(!checked)
                        }
                    }
                }

                // Подробности: подпись — значение, столбиком.
                Grid {
                    id: grid
                    visible: device.open
                    anchors { top: head.bottom; left: parent.left; leftMargin: 52 }
                    columns: 2
                    columnSpacing: 24
                    rowSpacing: 6
                    Repeater {
                        model: device.open ? device.entry.details.length * 2 : 0
                        SText {
                            required property int index
                            readonly property var pair: device.entry.details[Math.floor(index / 2)]
                            text: pair[index % 2]
                            color: index % 2 === 0 ? Theme.inkMuted : Theme.ink
                            size: Theme.fontSmall
                            // Адреса можно выделить и скопировать.
                        }
                    }
                }

                Rectangle {
                    visible: device.index < net.devices.length - 1
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 16; rightMargin: 16 }
                    height: 1
                    color: Theme.line
                }
            }
        }
    }

    SText {
        width: parent.width
        visible: net.message !== ""
        text: net.message
        color: net.messageIsError ? Theme.terracotta : Theme.green
        wrapMode: Text.Wrap
    }

    Card {
        title: "Сохранённые сети"
        visible: net.available
        SText {
            width: parent.width
            visible: net.connections.length === 0
            padding: 16
            text: "Сохранённых сетей нет. Подключитесь к Wi‑Fi в панели — сеть запомнится."
            color: Theme.inkMuted
            wrapMode: Text.Wrap
        }
        Repeater {
            model: net.connectionModel
            Item {
                id: conn
                required property var entry
                required property int index
                readonly property bool open: root.editing === entry.uuid
                width: parent.width
                implicitHeight: row.height + (open ? editor.height + 8 : 0)

                Item {
                    id: row
                    width: parent.width
                    height: Math.max(rowTexts.height, rowButtons.height) + 24
                    SIcon {
                        id: rowIcon
                        anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
                        size: 24
                        name: conn.entry.kind === "wifi" ? "network-wireless"
                            : conn.entry.kind === "wired" ? "network-wired"
                            : conn.entry.kind === "vpn" ? "network-vpn" : "network-connect"
                    }
                    Column {
                        id: rowTexts
                        anchors { left: rowIcon.right; leftMargin: 12; right: rowButtons.left; rightMargin: 16; verticalCenter: parent.verticalCenter }
                        spacing: 2
                        SText {
                            width: parent.width
                            text: conn.entry.name
                            elide: Text.ElideRight
                            weight: conn.entry.active ? 600 : 400
                        }
                        SText {
                            width: parent.width
                            text: [conn.entry.kindText,
                                   conn.entry.active ? "подключена" : conn.entry.activating ? "подключение…" : "",
                                   conn.entry.autoconnect ? "" : "сама не подключается",
                                   conn.entry.metered ? "лимитная" : "",
                                   conn.entry.ipManual && conn.entry.kind !== "vpn" ? "адрес " + conn.entry.address : ""]
                                  .filter(s => s !== "").join(" · ")
                            size: Theme.fontSmall
                            color: Theme.inkMuted
                            elide: Text.ElideRight
                        }
                    }
                    Row {
                        id: rowButtons
                        anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                        spacing: 8
                        SButton {
                            visible: !conn.entry.activating
                            text: conn.entry.active ? "Отключить" : "Подключить"
                            onClicked: conn.entry.active ? net.deactivate(conn.entry.uuid) : net.activate(conn.entry.uuid)
                        }
                        SButton {
                            text: conn.open ? "Свернуть" : "Настроить"
                            primary: conn.open
                            onClicked: root.edit(conn.entry)
                        }
                    }
                }

                Column {
                    id: editor
                    visible: conn.open
                    anchors { top: row.bottom; left: parent.left; right: parent.right; leftMargin: 36 }

                    Setting {
                        label: "Подключаться автоматически"
                        hint: conn.entry.kind === "vpn" ? "При каждом подключении к интернету"
                                                        : "Когда сеть рядом или кабель вставлен"
                        SSwitch {
                            checked: conn.entry.autoconnect
                            onToggled: net.setAutoconnect(conn.entry.uuid, !checked)
                        }
                    }
                    Setting {
                        visible: conn.entry.kind !== "vpn"
                        label: "Лимитное подключение"
                        hint: "Мобильный интернет или оплата за трафик: обновления не скачиваются сами"
                        SSwitch {
                            checked: conn.entry.metered
                            onToggled: net.setMetered(conn.entry.uuid, !checked)
                        }
                    }
                    Setting {
                        visible: conn.entry.kind === "wifi" && conn.entry.secured
                        label: "Пароль"
                        hint: root.passwordShown ? "Его можно продиктовать гостям или поменять, если сменили на роутере"
                                                 : "Сохранён в системе"
                        Row {
                            spacing: 8
                            SField {
                                visible: root.passwordShown
                                width: 200
                                text: root.passwordText
                                onTextEdited: root.passwordText = text
                                onAccepted: if (root.passwordText !== root.passwordLoaded) net.setPassword(root.editing, root.passwordText)
                            }
                            SButton {
                                visible: !root.passwordShown
                                text: "Показать"
                                onClicked: net.requestPassword(root.editing)
                            }
                            SButton {
                                visible: root.passwordShown && root.passwordText !== root.passwordLoaded
                                text: "Сохранить"
                                primary: true
                                onClicked: net.setPassword(root.editing, root.passwordText)
                            }
                        }
                    }
                    Setting {
                        visible: conn.entry.hasIpv4 && conn.entry.kind !== "vpn"
                        label: "IP-адрес"
                        hint: root.draftManual ? "Свой постоянный адрес — для сетей без DHCP или проброса портов" : "Выдаёт роутер (DHCP)"
                        Choice {
                            implicitWidth: 220
                            model: ["Автоматически", "Вручную"]
                            currentIndex: root.draftManual ? 1 : 0
                            onActivated: index => root.draftManual = index === 1
                        }
                    }
                    Setting {
                        visible: conn.entry.hasIpv4 && conn.entry.kind !== "vpn" && root.draftManual
                        label: "Адрес и маска"
                        Row {
                            spacing: 8
                            SField {
                                width: 150
                                placeholderText: "192.168.1.20"
                                text: root.draftAddress
                                onTextEdited: root.draftAddress = text
                            }
                            SField {
                                width: 150
                                placeholderText: "255.255.255.0"
                                text: root.draftMask
                                onTextEdited: root.draftMask = text
                            }
                        }
                    }
                    Setting {
                        visible: conn.entry.hasIpv4 && conn.entry.kind !== "vpn" && root.draftManual
                        label: "Шлюз"
                        hint: "Адрес роутера; пусто — без выхода в интернет"
                        SField {
                            width: 150
                            placeholderText: "192.168.1.1"
                            text: root.draftGateway
                            onTextEdited: root.draftGateway = text
                        }
                    }
                    Setting {
                        visible: conn.entry.hasIpv4 && conn.entry.kind !== "vpn"
                        label: "DNS-серверы"
                        hint: root.draftDnsManual ? "Через запятую, например 1.1.1.1, 8.8.8.8" : "Те, что сообщает сеть"
                        Column {
                            spacing: 8
                            Choice {
                                implicitWidth: 220
                                model: ["От сети", "Свои"]
                                currentIndex: root.draftDnsManual ? 1 : 0
                                onActivated: index => root.draftDnsManual = index === 1
                            }
                            SField {
                                visible: root.draftDnsManual
                                width: 220
                                placeholderText: "1.1.1.1, 8.8.8.8"
                                text: root.draftDns
                                onTextEdited: root.draftDns = text
                            }
                        }
                    }

                    Item {
                        width: parent.width
                        height: 56
                        SText {
                            anchors { left: parent.left; leftMargin: 16; right: actions.left; rightMargin: 16; verticalCenter: parent.verticalCenter }
                            text: root.draftError !== "" ? root.draftError : root.draftNote
                            color: root.draftError !== "" ? Theme.terracotta : Theme.green
                            size: Theme.fontSmall
                            wrapMode: Text.Wrap
                        }
                        Row {
                            id: actions
                            anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                            spacing: 8
                            SButton {
                                text: root.confirmForget === conn.entry.uuid ? "Точно забыть?" : "Забыть сеть"
                                danger: root.confirmForget === conn.entry.uuid
                                onClicked: {
                                    if (root.confirmForget === conn.entry.uuid) {
                                        root.confirmForget = "";
                                        net.forget(conn.entry.uuid);
                                    } else {
                                        root.confirmForget = conn.entry.uuid;
                                    }
                                }
                            }
                            SButton {
                                visible: root.draftDirty
                                text: conn.entry.active ? "Сохранить и переподключить" : "Сохранить"
                                primary: true
                                onClicked: root.saveAddressing()
                            }
                        }
                    }
                }

                Rectangle {
                    visible: conn.index < net.connections.length - 1
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 16; rightMargin: 16 }
                    height: 1
                    color: Theme.line
                }
            }
        }
    }

    Card {
        title: "Добавить"
        visible: net.available
        Setting {
            visible: net.wifiPresent
            label: "Скрытая сеть Wi‑Fi"
            hint: "Её нет в списке сетей рядом — подключиться по имени"
            last: !root.hiddenOpen
            SButton {
                text: root.hiddenOpen ? "Отмена" : "Подключиться…"
                onClicked: {
                    root.hiddenOpen = !root.hiddenOpen;
                    hiddenName.text = "";
                    hiddenPassword.text = "";
                    if (root.hiddenOpen) hiddenName.forceActiveFocus();
                }
            }
        }
        Setting {
            visible: net.wifiPresent && root.hiddenOpen
            label: "Имя сети и пароль"
            hint: "Пароль пустой — сеть без пароля"
            Row {
                spacing: 8
                SField {
                    id: hiddenName
                    width: 150
                    placeholderText: "Имя сети"
                }
                SField {
                    id: hiddenPassword
                    width: 150
                    placeholderText: "Пароль"
                    echoMode: TextInput.Password
                    onAccepted: hiddenConnect.clicked()
                }
                SButton {
                    id: hiddenConnect
                    text: "Подключиться"
                    primary: true
                    enabled: hiddenName.text.trim() !== ""
                    opacity: enabled ? 1 : 0.5
                    onClicked: {
                        net.connectHidden(hiddenName.text, hiddenPassword.text);
                        root.hiddenOpen = false;
                    }
                }
            }
        }
        Setting {
            last: true
            label: "VPN из файла"
            hint: net.openVpnSupported ? "WireGuard (.conf) или OpenVPN (.ovpn) — файл даёт VPN-сервис"
                                       : "WireGuard (.conf) — файл даёт VPN-сервис"
            SButton {
                text: "Выбрать файл…"
                onClicked: vpnDialog.open()
            }
        }
    }

    SText {
        width: parent.width
        visible: net.available
        text: "Сети рядом и подключение к новой — в панели: «Сеть» в быстрых настройках."
        size: Theme.fontSmall
        color: Theme.inkMuted
        wrapMode: Text.Wrap
    }

    FileDialog {
        id: vpnDialog
        title: "Файл VPN"
        currentFolder: StandardPaths.writableLocation(StandardPaths.DownloadLocation)
        nameFilters: net.openVpnSupported ? ["Файлы VPN (*.conf *.ovpn)"] : ["WireGuard (*.conf)"]
        onAccepted: net.importVpn(selectedFile.toString())
    }
}
