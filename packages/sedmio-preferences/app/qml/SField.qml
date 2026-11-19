import QtQuick
import QtQuick.Controls
import Sedmio.Style

// Поле ввода в стиле «Параметров».
TextField {
    id: field
    property bool invalid: false

    implicitWidth: 260
    implicitHeight: 34
    leftPadding: 12
    rightPadding: 12
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontBody
    color: Theme.ink
    placeholderTextColor: Theme.inkMuted
    selectionColor: Theme.greenSelect
    selectedTextColor: Theme.ink
    verticalAlignment: TextInput.AlignVCenter

    background: Rectangle {
        radius: 10
        color: Theme.surface
        border.width: field.activeFocus || field.invalid ? 2 : 1
        border.color: field.invalid ? Theme.terracotta : field.activeFocus ? Theme.green : Theme.line
    }
}
