import QtQuick
import io.calamares.core 1.0
import io.calamares.ui 1.0
import "components"

// Пользователь. Человек вводит только имя (любое) и пароль.
// Логин латиницей и имя компьютера Calamares создаёт из имени сам,
// они спрятаны в «Дополнительно».
// config: модуль users.
SPage {
    id: page

    stage: 4
    centerVertically: false

    property bool showAdvanced: false

    readonly property bool passwordsMatch: config.userPassword === config.userPasswordSecondary
    // 0 — годится, 1 — слабый (разрешён), 2 — не годится
    readonly property bool passwordInvalid: config.userPassword !== "" && config.userPasswordValidity === 2

    function onActivate() {
        page.replayAppear()
        nameField.input.forceActiveFocus()
    }

    PageHeader {
        width: parent.width
        eyebrow: "Пользователь"
        title: "Как вас зовут?"
        subtitle: "Это имя будет на экране входа. Пишите как удобно, можно по‑русски."
    }

    STextField {
        id: nameField
        width: parent.width
        label: "Имя"
        placeholderText: "Например, Иван"
        text: config.fullName
        onTextEdited: config.setFullName(text)
    }

    Row {
        width: parent.width
        spacing: 14

        STextField {
            width: (parent.width - parent.spacing) / 2
            label: "Пароль"
            echoMode: TextInput.Password
            text: config.userPassword
            onTextEdited: config.setUserPassword(text)
            error: page.passwordInvalid
            hint: page.passwordInvalid ? config.userPasswordMessage : ""
        }

        STextField {
            width: (parent.width - parent.spacing) / 2
            label: "Ещё раз"
            echoMode: TextInput.Password
            text: config.userPasswordSecondary
            onTextEdited: config.setUserPasswordSecondary(text)
            error: text !== "" && !page.passwordsMatch
            hint: error ? "Пароли не совпадают" : ""
        }
    }

    SSwitch {
        width: parent.width
        text: "Входить без пароля"
        description: "Рабочий стол откроется сразу после включения. Пароль всё равно понадобится для системных настроек."
        checked: config.doAutoLogin
        onToggled: config.setAutoLogin(checked)
    }

    // «Дополнительно»: логин и имя компьютера
    Column {
        width: parent.width
        spacing: 18

        Item {
            width: advancedRow.implicitWidth
            height: advancedRow.implicitHeight

            Row {
                id: advancedRow
                spacing: 8

                Text {
                    id: advancedLabel
                    text: "Дополнительно"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontBody
                    font.weight: Font.Medium
                    color: advancedMouse.containsMouse ? Theme.greenHover : Theme.green
                }
                Text {
                    anchors.verticalCenter: advancedLabel.verticalCenter
                    text: "›"
                    rotation: page.showAdvanced ? 90 : 0
                    font.pixelSize: Theme.fontLarge
                    color: advancedLabel.color
                    Behavior on rotation { SpringAnimation { spring: 4; damping: 0.3 } }
                }
            }

            MouseArea {
                id: advancedMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    page.showAdvanced = !page.showAdvanced
                    if (page.showAdvanced)
                        Qt.callLater(page.scrollToEnd)
                }
            }
        }

        Row {
            width: parent.width
            spacing: 14
            visible: page.showAdvanced

            STextField {
                width: (parent.width - parent.spacing) / 2
                label: "Логин"
                text: config.loginName
                onTextEdited: config.setLoginName(text)
                error: config.loginNameStatus !== ""
                hint: error ? config.loginNameStatus : "Латиницей, из имени. Нужен только системе."
            }

            STextField {
                width: (parent.width - parent.spacing) / 2
                label: "Имя компьютера"
                text: config.hostname
                onTextEdited: config.setHostName(text)
                error: config.hostnameStatus !== ""
                hint: error ? config.hostnameStatus : "Так компьютер виден в домашней сети."
            }
        }
    }
}
