import QtQuick
import Quickshell
import Sedmio.Style

// Верхняя панель макетов "dock" и "taskbar", часть рамки. Посередине —
// дата и часы (клик — календарь), справа — трей и кнопки состояния
// (StatusButtons, без часов).
Item {
    id: bar
    required property var window     // окно рамки: меню трея
    required property string screenName
    required property Item tooltip

    PanelMenu {
        anchors.fill: parent
        window: bar.window
    }

    Clock {
        id: clock
        anchors.centerIn: parent
        wide: true
        size: DesktopLayout.topButton
        screenName: bar.screenName
        tooltip: bar.tooltip
    }

    Row {
        anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
        spacing: 2

        Tray {
            anchors.verticalCenter: parent.verticalCenter
            horizontal: true
            buttonSize: DesktopLayout.topButton
            window: bar.window
            tooltip: bar.tooltip
        }

        StatusButtons {
            anchors.verticalCenter: parent.verticalCenter
            width: implicitWidth
            height: implicitHeight
            horizontal: true
            exclude: ["clock"]
            buttonSize: DesktopLayout.topButton
            screenName: bar.screenName
            tooltip: bar.tooltip
        }
    }
}
