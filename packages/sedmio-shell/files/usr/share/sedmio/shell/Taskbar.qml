import QtQuick
import Sedmio.Style

// Нижняя панель задач макета "taskbar", часть рамки: знак Sedmio (запуск
// программ, правый клик — меню быстрых ссылок), закреплённые программы и
// окна с подписями.
Item {
    id: bar
    required property var window
    required property string screenName
    required property Item tooltip

    PanelMenu {
        anchors.fill: parent
        window: bar.window
    }

    LauncherButton {
        id: launcher
        anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
        screenName: bar.screenName
        tooltip: bar.tooltip
    }

    Rectangle {
        id: separator
        anchors { left: launcher.right; leftMargin: 8; verticalCenter: parent.verticalCenter }
        width: 2
        height: 22
        radius: 1
        color: Theme.line
    }

    WindowList {
        anchors {
            left: separator.right; leftMargin: 8
            right: parent.right; rightMargin: 8
            top: parent.top; bottom: parent.bottom
        }
        horizontal: true
        labeled: true
        window: bar.window
        tooltip: bar.tooltip
    }
}
