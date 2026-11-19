import QtQuick
import Sedmio.Style

// Поле пароля: точки вместо букв, глазок — показать набранное.
Rectangle {
    id: root
    property alias text: input.text
    property string placeholder: "Пароль"
    property bool error: false
    property bool reveal: false
    property bool allowReveal: true
    property alias inputEnabled: input.enabled
    signal accepted()
    signal escapePressed()

    function focusInput() { input.forceActiveFocus(); }
    function clear() { input.text = ""; }

    implicitHeight: 44
    radius: 12
    color: Theme.surface
    border.width: 1
    border.color: error ? Theme.terracotta : input.activeFocus ? Theme.lineStrong : Theme.line

    TextInput {
        id: input
        anchors { left: parent.left; leftMargin: 14; right: eye.left; rightMargin: 6; verticalCenter: parent.verticalCenter }
        echoMode: root.reveal ? TextInput.Normal : TextInput.Password
        passwordCharacter: "•"
        font.family: Theme.fontFamily
        font.pixelSize: 15
        color: Theme.ink
        clip: true
        focus: true
        Keys.onReturnPressed: root.accepted()
        Keys.onEnterPressed: root.accepted()
        Keys.onEscapePressed: root.escapePressed()

        SText {
            anchors.verticalCenter: parent.verticalCenter
            visible: input.text === ""
            text: root.placeholder
            color: Theme.inkMuted
        }
    }

    Rectangle {
        id: eye
        visible: root.allowReveal
        anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
        width: root.allowReveal ? 32 : 0
        height: 32
        radius: 9
        color: eyeArea.containsMouse ? Theme.paperDeep : "transparent"
        SIcon {
            anchors.centerIn: parent
            implicitSize: 18
            name: root.reveal ? "view-hidden" : "view-visible"
        }
        MouseArea {
            id: eyeArea
            anchors.fill: parent
            hoverEnabled: true
            onClicked: { root.reveal = !root.reveal; input.forceActiveFocus(); }
        }
    }
}
