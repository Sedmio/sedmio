import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Kde
import Quickshell.Wayland

// Пароль от сети, когда его просит NetworkManager: новая сеть, сменили
// пароль или прежний не подошёл. Вместо окна plasma-nm.
ModalWindow {
    id: root
    required property NetworkSecretAgent agent

    active: agent.active
    WlrLayershell.namespace: "sedmio-network-password"
    iconName: "network-wireless"
    title: agent.retry ? "Пароль не подошёл" : "Пароль от сети"
    subtitle: agent.networkName !== "" ? "«" + agent.networkName + "»" : ""

    property string error: ""

    function submit() {
        const text = password.text;
        if (agent.kind === "psk" && (text.length < 8 || text.length > 63)) {
            error = "Пароль Wi‑Fi — от 8 до 63 символов";
            shake();
            return;
        }
        if (text.length === 0) {
            shake();
            return;
        }
        agent.respond(text);
    }

    onActiveChanged: {
        if (!active) return;
        error = "";
        password.clear();
        password.reveal = false;
        password.focusInput();
    }

    // Следующий запрос сразу за предыдущим — очистить поле.
    Connections {
        target: root.agent
        function onRequestChanged() {
            if (!root.agent.active) return;
            root.error = "";
            password.clear();
            if (root.agent.retry) root.shake();
            password.focusInput();
        }
    }

    SText {
        Layout.fillWidth: true
        text: root.agent.retry
            ? "Сеть не приняла пароль. Проверьте его и введите ещё раз."
            : root.agent.kind === "enterprise"
                ? "Сеть просит пароль учётной записи" + (root.agent.identity !== "" ? " " + root.agent.identity : "") + "."
                : "Введите пароль, чтобы подключиться."
        wrapMode: Text.Wrap
        color: Theme.inkSoft
    }

    PasswordField {
        id: password
        Layout.fillWidth: true
        error: root.error !== "" || root.agent.retry
        onAccepted: root.submit()
        onEscapePressed: root.agent.cancel()
    }

    SText {
        Layout.fillWidth: true
        visible: root.error !== ""
        text: root.error
        color: Theme.terracotta
        size: 13
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 4
        spacing: 8
        Item { Layout.fillWidth: true }
        SButton { text: "Отмена"; onClicked: root.agent.cancel() }
        SButton { text: "Подключиться"; primary: true; onClicked: root.submit() }
    }
}
