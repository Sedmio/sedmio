import QtCore
import QtQuick
import QtQuick.Dialogs
import QtQuick.Effects
import Sedmio.Preferences
import Sedmio.Style

// «Учётная запись»: картинка и имя (их показывают экран входа и экран
// блокировки), пароль, вход без пароля.
Page {
    id: root
    title: "Учётная запись"

    Account {
        id: account
        onPasswordChanged: {
            newPassword.text = "";
            repeatPassword.text = "";
        }
    }

    readonly property bool passwordsMatch: newPassword.text === repeatPassword.text
    readonly property bool canChangePassword: newPassword.text !== "" && passwordsMatch && !account.busy

    SText {
        visible: !account.ready
        width: parent.width
        text: "Служба учётных записей (AccountsService) не отвечает — изменить имя, картинку и пароль сейчас нельзя."
        color: Theme.terracotta
        wrapMode: Text.Wrap
    }

    // Картинка, имя, логин.
    Card {
        visible: account.ready
        Item {
            width: parent.width
            height: 128

            Item {
                id: avatar
                x: 20
                anchors.verticalCenter: parent.verticalCenter
                width: 88
                height: 88

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: Theme.greenWash
                    border.width: 1
                    border.color: Theme.line
                    // Круг и под картинкой: у прозрачных картинок иначе нет границы.
                    SText {
                        anchors.centerIn: parent
                        visible: picture.status !== Image.Ready
                        text: (account.realName || account.userName).charAt(0).toUpperCase()
                        size: 38
                        weight: 550
                        color: Theme.green
                    }
                }
                Image {
                    id: picture
                    anchors.fill: parent
                    source: account.avatar
                    sourceSize: Qt.size(width * 2, height * 2)
                    fillMode: Image.PreserveAspectCrop
                    cache: false
                    visible: false
                }
                Rectangle {
                    id: mask
                    anchors.fill: parent
                    radius: width / 2
                    visible: false
                    layer.enabled: true
                }
                MultiEffect {
                    anchors.fill: parent
                    source: picture
                    maskEnabled: true
                    maskSource: mask
                    visible: picture.status === Image.Ready
                }
                // Наведение — «сменить».
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: Theme.shadow
                    opacity: avatarArea.containsMouse ? 0.35 : 0
                    Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
                    SIcon {
                        anchors.centerIn: parent
                        name: "camera-photo"
                        size: 22
                        visible: avatarArea.containsMouse
                    }
                }
                MouseArea {
                    id: avatarArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (!account.busy) avatarDialog.open()
                }
            }

            Column {
                anchors { left: avatar.right; leftMargin: 20; right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                spacing: 4
                SText {
                    width: parent.width
                    text: account.realName || account.userName
                    size: 20
                    weight: 600
                    elide: Text.ElideRight
                }
                SText {
                    width: parent.width
                    text: "Имя для входа: " + account.userName
                    color: Theme.inkMuted
                    size: Theme.fontSmall
                }
                Row {
                    topPadding: 6
                    spacing: 8
                    SButton {
                        text: "Сменить картинку"
                        onClicked: if (!account.busy) avatarDialog.open()
                    }
                    SButton {
                        visible: account.avatar.toString() !== ""
                        text: "Убрать"
                        onClicked: if (!account.busy) account.removeAvatar()
                    }
                }
            }
        }
    }

    Card {
        title: "Имя"
        visible: account.ready
        Setting {
            label: "Как вас называть"
            hint: "Показывается на экране входа и блокировки"
            last: true
            Row {
                spacing: 8
                SField {
                    id: nameField
                    width: 220
                    text: account.realName
                    placeholderText: account.userName
                    maximumLength: 64
                    // Двоеточие и запятая ломают /etc/passwd.
                    validator: RegularExpressionValidator { regularExpression: /[^:,]*/ }
                    onAccepted: account.setRealName(text)
                }
                SButton {
                    text: "Сохранить"
                    primary: true
                    visible: nameField.text.trim() !== account.realName && nameField.text.trim() !== ""
                    onClicked: account.setRealName(nameField.text)
                }
            }
        }
    }

    Card {
        title: "Пароль"
        visible: account.ready
        Setting {
            label: "Новый пароль"
            SField {
                id: newPassword
                width: 260
                echoMode: TextInput.Password
                placeholderText: "Новый пароль"
            }
        }
        Setting {
            label: "Ещё раз"
            hint: newPassword.text !== "" && repeatPassword.text !== "" && !root.passwordsMatch ? "Пароли не совпадают" : ""
            SField {
                id: repeatPassword
                width: 260
                echoMode: TextInput.Password
                placeholderText: "Повторите пароль"
                invalid: text !== "" && !root.passwordsMatch
                onAccepted: if (root.canChangePassword) account.changePassword(newPassword.text)
            }
        }
        Setting {
            last: true
            label: ""
            hint: "Сначала система спросит нынешний пароль"
            SButton {
                text: "Сменить пароль"
                primary: root.canChangePassword
                opacity: root.canChangePassword ? 1 : 0.5
                onClicked: if (root.canChangePassword) account.changePassword(newPassword.text)
            }
        }
    }

    Card {
        title: "Вход"
        visible: account.ready && account.autologinAvailable
        Setting {
            last: true
            label: "Входить без пароля"
            hint: account.autologinOther !== ""
                  ? "Сейчас без пароля входит " + account.autologinOther + ". Включите — будете входить вы."
                  : "После включения компьютера рабочий стол откроется сразу. Экран блокировки всё равно спросит пароль."
            SSwitch {
                checked: account.autologin
                opacity: account.busy ? 0.5 : 1
                onToggled: if (!account.busy) account.setAutologin(!account.autologin)
            }
        }
    }

    SText {
        visible: account.message !== ""
        width: parent.width
        text: account.message
        color: account.messageIsError ? Theme.terracotta : Theme.green
        wrapMode: Text.Wrap
    }

    FileDialog {
        id: avatarDialog
        title: "Картинка учётной записи"
        nameFilters: ["Картинки (*.png *.jpg *.jpeg *.webp *.bmp *.gif)"]
        // Свои фото — в «Изображениях», а не набор Konqi из Plasma.
        currentFolder: StandardPaths.writableLocation(StandardPaths.PicturesLocation)
        onAccepted: account.setAvatar(selectedFile)
    }
}
