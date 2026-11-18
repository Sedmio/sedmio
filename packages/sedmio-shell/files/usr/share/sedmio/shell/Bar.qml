import QtQuick
import QtQuick.Layouts

// Панель слева, часть рамки. Сверху знак Sedmio и открытые окна,
// снизу трей, звук и часы.
Item {
    id: bar
    required property var window     // окно рамки: меню трея, сворачивание
    required property string screenName
    required property Item tooltip

    ColumnLayout {
        id: topGroup
        anchors { top: parent.top; left: parent.left; right: parent.right; topMargin: Theme.border + 2 }
        spacing: 8

        LauncherButton {
            Layout.alignment: Qt.AlignHCenter
            screenName: bar.screenName
            tooltip: bar.tooltip
        }

        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: 22
            implicitHeight: 2
            radius: 1
            color: Theme.line
        }
    }

    WindowList {
        anchors {
            top: topGroup.bottom; topMargin: 8
            bottom: bottomGroup.top; bottomMargin: 8
            left: parent.left; right: parent.right
        }
        window: bar.window
        tooltip: bar.tooltip
    }

    ColumnLayout {
        id: bottomGroup
        anchors { bottom: parent.bottom; left: parent.left; right: parent.right; bottomMargin: Theme.border + 6 }
        spacing: 6

        Tray {
            Layout.alignment: Qt.AlignHCenter
            window: bar.window
            tooltip: bar.tooltip
        }

        Volume {
            Layout.alignment: Qt.AlignHCenter
            tooltip: bar.tooltip
        }

        Clock {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 4
            tooltip: bar.tooltip
        }
    }
}
