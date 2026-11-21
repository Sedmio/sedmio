import QtQuick
import QtQuick.Layouts
import Quickshell
import Sedmio.Style

// Панель слева, часть рамки (макет "left"). Сверху знак Sedmio и
// открытые окна, снизу трей и кнопки состояния (StatusButtons).
Item {
    id: bar
    required property var window     // окно рамки: меню трея, сворачивание
    required property string screenName
    required property Item tooltip

    PanelMenu {
        anchors.fill: parent
        window: bar.window
    }

    ColumnLayout {
        id: topGroup
        anchors { top: parent.top; left: parent.left; right: parent.right; topMargin: Theme.border + 4 }
        spacing: 8

        LauncherButton {
            Layout.alignment: Qt.AlignHCenter
            size: DesktopLayout.leftButton
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
        buttonSize: DesktopLayout.leftButton
        window: bar.window
        tooltip: bar.tooltip
    }

    ColumnLayout {
        id: bottomGroup
        anchors { bottom: parent.bottom; left: parent.left; right: parent.right; bottomMargin: Theme.border }
        spacing: 6

        Tray {
            Layout.alignment: Qt.AlignHCenter
            buttonSize: DesktopLayout.leftButton
            window: bar.window
            tooltip: bar.tooltip
        }

        StatusButtons {
            Layout.fillWidth: true
            Layout.preferredHeight: implicitHeight
            buttonSize: DesktopLayout.leftButton
            screenName: bar.screenName
            tooltip: bar.tooltip
        }
    }
}
