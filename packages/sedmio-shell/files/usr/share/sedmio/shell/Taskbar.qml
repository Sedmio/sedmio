import QtQuick
import Sedmio.Style

// Нижняя панель задач макета "taskbar", часть рамки: знак Sedmio (запуск
// программ, правый клик — меню быстрых ссылок), закреплённые программы и
// окна с подписями, у правого края — «Показать рабочий стол».
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
        size: DesktopLayout.taskbarButton
        screenName: bar.screenName
        tooltip: bar.tooltip
    }

    Rectangle {
        id: separator
        anchors { left: launcher.right; leftMargin: 8; verticalCenter: parent.verticalCenter }
        width: 2
        height: Math.round(DesktopLayout.taskbarButton * 0.6)
        radius: 1
        color: Theme.line
    }

    WindowList {
        anchors {
            left: separator.right; leftMargin: 8
            right: desktopSeparator.left; rightMargin: 8
            top: parent.top; bottom: parent.bottom
        }
        horizontal: true
        labeled: true
        buttonSize: DesktopLayout.taskbarButton
        window: bar.window
        tooltip: bar.tooltip
    }

    Rectangle {
        id: desktopSeparator
        anchors { right: desktopButton.left; rightMargin: 6; verticalCenter: parent.verticalCenter }
        width: 2
        height: Math.round(DesktopLayout.taskbarButton * 0.6)
        radius: 1
        color: Theme.line
    }

    // Как в Windows: щелчок прячет все окна, ещё щелчок — возвращает.
    BarButton {
        id: desktopButton
        anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
        size: DesktopLayout.taskbarButton
        tooltip: bar.tooltip
        hint: "Рабочий стол"
        onClicked: {
            if (tooltip) tooltip.hide();
            ShellState.closeAll(false);
            ShellState.showDesktop();
        }

        SIcon {
            anchors.centerIn: parent
            implicitSize: desktopButton.iconSize
            name: "desktop-symbolic"
            fallback: "user-desktop"
        }
    }
}
