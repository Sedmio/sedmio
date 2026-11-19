import QtQuick

// Строка параметра: подпись (и пояснение) слева, управление справа.
Item {
    id: root
    property string label
    property string hint
    property bool last: false
    default property alias control: slot.data

    width: parent ? parent.width : 0
    implicitHeight: Math.max(texts.height, slot.childrenRect.height) + 24

    Column {
        id: texts
        anchors { left: parent.left; leftMargin: 16; right: slot.left; rightMargin: 16; verticalCenter: parent.verticalCenter }
        spacing: 2
        SText {
            width: parent.width
            text: root.label
            wrapMode: Text.Wrap
        }
        SText {
            width: parent.width
            visible: root.hint !== ""
            text: root.hint
            size: Theme.fontSmall
            color: Theme.inkMuted
            wrapMode: Text.Wrap
        }
    }

    Item {
        id: slot
        anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
        width: childrenRect.width
        height: childrenRect.height
    }

    Rectangle {
        visible: !root.last
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 16; rightMargin: 16 }
        height: 1
        color: Theme.line
    }
}
