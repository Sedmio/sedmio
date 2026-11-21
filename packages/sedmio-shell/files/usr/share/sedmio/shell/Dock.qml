import QtQuick
import Sedmio.Style

// Док макета "dock": короткая полоса по центру внизу — знак Sedmio
// (запуск программ, правый клик — меню быстрых ссылок), закреплённые
// программы и окна. Фон и тень рисует рамка (Frame), здесь — содержимое.
Item {
    id: dock
    required property var window
    required property string screenName
    required property Item tooltip
    // Сколько места можно занять по ширине.
    property real maxWidth: 1000

    readonly property real padding: 8
    implicitWidth: Math.min(maxWidth, padding + launcher.width + 8 + 2 + 8 + list.contentWidth + padding)
    implicitHeight: DesktopLayout.dockHeight

    PanelMenu {
        anchors.fill: parent
        window: dock.window
    }

    LauncherButton {
        id: launcher
        anchors { left: parent.left; leftMargin: dock.padding; verticalCenter: parent.verticalCenter }
        screenName: dock.screenName
        tooltip: dock.tooltip
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
        id: list
        anchors {
            left: separator.right; leftMargin: 8
            right: parent.right; rightMargin: dock.padding
            verticalCenter: parent.verticalCenter
        }
        height: Theme.buttonSize + 8
        horizontal: true
        window: dock.window
        tooltip: dock.tooltip
    }
}
