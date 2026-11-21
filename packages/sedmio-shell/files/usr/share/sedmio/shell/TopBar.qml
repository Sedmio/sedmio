import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Sedmio.Style

// Верхняя панель макетов "dock" и "taskbar", часть рамки. Слева — значок
// и заголовок активного окна (если оно на этом экране), посередине — дата
// и часы (клик — календарь), справа — трей и кнопки состояния
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

    readonly property var active: ToplevelManager.activeToplevel
    readonly property bool activeHere: !!active && active.screens.length > 0
        && active.screens[0]?.name === bar.screenName
    readonly property var activeEntry: activeHere && active.appId ? DesktopEntries.heuristicLookup(active.appId) : null

    // Сколько места до часов.
    readonly property real titleRoom: clock.x - 24 - 14

    Row {
        id: title
        anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
        spacing: 8
        visible: bar.activeHere && bar.titleRoom > 60

        IconImage {
            anchors.verticalCenter: parent.verticalCenter
            implicitSize: 18
            source: Icons.path(bar.activeEntry?.icon ?? bar.active?.appId ?? "", true)
                || Icons.path("application-x-executable")
        }
        SText {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, bar.titleRoom - 26)
            elide: Text.ElideRight
            text: bar.active?.title ?? ""
            size: Theme.fontBody
            weight: 550
        }
    }

    Clock {
        id: clock
        anchors.centerIn: parent
        wide: true
        screenName: bar.screenName
        tooltip: bar.tooltip
    }

    Row {
        anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
        spacing: 2

        Tray {
            anchors.verticalCenter: parent.verticalCenter
            horizontal: true
            window: bar.window
            tooltip: bar.tooltip
        }

        StatusButtons {
            anchors.verticalCenter: parent.verticalCenter
            width: implicitWidth
            height: implicitHeight
            horizontal: true
            exclude: ["clock"]
            screenName: bar.screenName
            tooltip: bar.tooltip
        }
    }
}
