import QtQuick
import QtQuick.Layouts
import Sedmio.Style

// Заголовок страницы панели управления: «назад», название, переключатель.
RowLayout {
    id: root
    property string title
    property bool showSwitch: false
    property bool showBack: true
    property bool checked: false
    signal back()
    signal toggled()

    spacing: 8

    Rectangle {
        visible: root.showBack
        implicitWidth: 34
        implicitHeight: 34
        radius: 11
        color: backArea.containsMouse ? Theme.paperDeep : Qt.alpha(Theme.paperDeep, 0)
        SIcon { anchors.centerIn: parent; implicitSize: 18; name: "go-previous" }
        MouseArea {
            id: backArea
            anchors.fill: parent
            hoverEnabled: true
            onClicked: root.back()
        }
    }

    SText {
        Layout.fillWidth: true
        text: root.title
        size: 17
        weight: 650
    }

    SSwitch {
        visible: root.showSwitch
        checked: root.checked
        onToggled: root.toggled()
    }
}
