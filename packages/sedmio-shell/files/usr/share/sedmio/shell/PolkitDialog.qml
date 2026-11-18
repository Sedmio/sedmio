import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Polkit
import Quickshell.Wayland

// Запрос пароля администратора (polkit): программа просит права на
// действие. Вместо polkit-kde-agent.
ModalWindow {
    id: root
    required property PolkitAgent agent
    readonly property var flow: agent.flow

    active: agent.isActive && flow !== null
    WlrLayershell.namespace: "sedmio-polkit"
    iconName: flow && flow.iconName !== "" ? flow.iconName : "system-lock-screen"
    title: "Нужен пароль администратора"
    subtitle: {
        const ids = flow ? flow.identities : [];
        const who = flow && flow.selectedIdentity ? flow.selectedIdentity : (ids.length > 0 ? ids[0] : null);
        return who ? "Пароль пользователя " + (who.displayName || who.string) : "";
    }

    property string error: ""

    function submit() {
        if (!flow || !flow.isResponseRequired) return;
        error = "";
        flow.submit(password.text);
        password.clear();
    }

    function cancel() {
        if (flow) flow.cancelAuthenticationRequest();
    }

    onActiveChanged: {
        if (!active) return;
        error = "";
        password.clear();
        password.focusInput();
    }

    Connections {
        target: root.flow
        function onAuthenticationFailed() {
            root.error = "Неверный пароль, попробуйте ещё раз";
            root.shake();
            password.focusInput();
        }
        function onIsResponseRequiredChanged() {
            if (root.flow.isResponseRequired) password.focusInput();
        }
    }

    // Что именно просят (описание действия polkit, уже по-русски)
    SText {
        Layout.fillWidth: true
        text: root.flow ? root.flow.message : ""
        wrapMode: Text.Wrap
        color: Theme.inkSoft
        lineHeight: 1.1
    }

    // Несколько администраторов — выбрать, чей пароль вводить
    Flow {
        Layout.fillWidth: true
        spacing: 6
        visible: root.flow !== null && root.flow.identities.length > 1
        Repeater {
            model: root.flow ? root.flow.identities : []
            SButton {
                required property var modelData
                text: modelData.displayName || modelData.string
                primary: root.flow && root.flow.selectedIdentity === modelData
                onClicked: root.flow.selectedIdentity = modelData
            }
        }
    }

    PasswordField {
        id: password
        Layout.fillWidth: true
        error: root.error !== ""
        // PAM может попросить и не секретное (код подтверждения) — тогда видно.
        reveal: root.flow !== null && root.flow.responseVisible
        allowReveal: false
        inputEnabled: root.flow !== null && root.flow.isResponseRequired
        placeholder: root.flow && !root.flow.isResponseRequired ? "Проверяем…" : "Пароль"
        onAccepted: root.submit()
        onEscapePressed: root.cancel()
    }

    // Ошибка или подсказка от системы (второй фактор и т.п.)
    SText {
        Layout.fillWidth: true
        visible: text !== ""
        text: root.error !== "" ? root.error
            : root.flow && root.flow.supplementaryMessage !== "" ? root.flow.supplementaryMessage : ""
        color: root.error !== "" || (root.flow && root.flow.supplementaryIsError) ? Theme.terracotta : Theme.inkMuted
        size: 13
        wrapMode: Text.Wrap
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 4
        spacing: 8
        Item { Layout.fillWidth: true }
        SButton { text: "Отмена"; onClicked: root.cancel() }
        SButton { text: "Подтвердить"; primary: true; onClicked: root.submit() }
    }
}
