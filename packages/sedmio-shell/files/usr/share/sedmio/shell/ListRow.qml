import QtQuick
import QtQuick.Layouts
import Sedmio.Style

// Строка списка на страницах панели (сеть, устройство, выход звука).
// Под строкой можно положить дополнительное содержимое — оно появляется
// при раскрытии (поле пароля, кнопки).
Rectangle {
    id: root
    property string icon
    property string title
    property string subtitle
    property string trailingIcon
    property bool selected: false
    property bool emphasized: false
    default property alias extra: extraColumn.data

    signal clicked()

    implicitHeight: 48 + (extraColumn.visibleChildren.length > 0 ? extraColumn.implicitHeight + 10 : 0)
    radius: 12
    color: selected ? Theme.greenWash : (area.containsMouse ? Theme.paperDeep : "transparent")
    Behavior on color { ColorAnimation { duration: Theme.animFast } }

    MouseArea {
        id: area
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 48
        hoverEnabled: true
        onClicked: root.clicked()
    }

    RowLayout {
        anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 12; rightMargin: 12 }
        height: 48
        spacing: 12

        SIcon { name: root.icon; visible: root.icon !== "" }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            SText {
                Layout.fillWidth: true
                text: root.title
                elide: Text.ElideRight
                weight: root.emphasized || root.selected ? 600 : 450
            }
            SText {
                Layout.fillWidth: true
                visible: text !== ""
                text: root.subtitle
                elide: Text.ElideRight
                size: Theme.fontSmall
                color: Theme.inkMuted
            }
        }

        SIcon {
            visible: root.trailingIcon !== ""
            implicitSize: 16
            name: root.trailingIcon
        }
    }

    ColumnLayout {
        id: extraColumn
        anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: 48; leftMargin: 12; rightMargin: 12 }
        spacing: 8
    }
}
