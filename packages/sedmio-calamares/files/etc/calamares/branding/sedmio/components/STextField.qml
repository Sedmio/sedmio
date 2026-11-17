import QtQuick
import QtQuick.Templates as T

// Поле ввода: подпись сверху, светлая подложка, при фокусе — зелёная
// рамка и мягкое свечение. error — терракотовая рамка и текст под полем.
Column {
    id: root

    property alias text: field.text
    property alias placeholderText: field.placeholderText
    property alias echoMode: field.echoMode
    property alias validator: field.validator
    property alias input: field
    property string label: ""
    property string hint: ""
    property bool error: false

    signal textEdited()

    spacing: 8

    Text {
        visible: root.label !== ""
        text: root.label
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSmall
        font.weight: Font.Medium
        color: Theme.inkSoft
    }

    T.TextField {
        id: field

        width: root.width
        implicitHeight: Theme.controlHeight
        leftPadding: 16
        rightPadding: 16
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontBody
        color: Theme.ink
        selectionColor: Theme.leafLight
        selectedTextColor: Theme.ink
        placeholderTextColor: Theme.inkMuted
        verticalAlignment: TextInput.AlignVCenter
        hoverEnabled: true
        onTextEdited: root.textEdited()

        Text {
            anchors.fill: parent
            anchors.leftMargin: field.leftPadding
            verticalAlignment: Text.AlignVCenter
            visible: field.text === ""
            text: field.placeholderText
            font: field.font
            color: field.placeholderTextColor
            elide: Text.ElideRight
        }

        background: Item {
            // Свечение фокуса: мягкий ореол вокруг поля
            Rectangle {
                anchors.fill: parent
                anchors.margins: -4
                radius: Theme.radius + 4
                color: "transparent"
                border.width: 4
                border.color: root.error ? Theme.terracottaSoft : Theme.greenWash
                opacity: field.activeFocus ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.animNormal } }
            }

            Rectangle {
                anchors.fill: parent
                radius: Theme.radius
                color: Theme.surface
                border.width: field.activeFocus || root.error ? 1.5 : 1
                border.color: root.error ? Theme.danger
                            : field.activeFocus ? Theme.green
                            : field.hovered ? Theme.lineStrong
                            : Theme.line
                Behavior on border.color { ColorAnimation { duration: Theme.animFast } }
            }
        }
    }

    Text {
        visible: root.hint !== ""
        width: root.width
        text: root.hint
        wrapMode: Text.WordWrap
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSmall
        color: root.error ? Theme.danger : Theme.inkMuted
    }
}
