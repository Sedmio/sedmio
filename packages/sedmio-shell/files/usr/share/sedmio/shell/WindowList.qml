import QtQuick
import Quickshell.Wayland

// Открытые окна. Список даёт ToplevelManager — в нашей сборке
// Quickshell он работает и под KWin (org_kde_plasma_window_management).
ListView {
    id: list
    required property var window
    required property Item tooltip

    clip: true
    spacing: 4
    boundsBehavior: Flickable.StopAtBounds
    model: ToplevelManager.toplevels

    delegate: WindowButton {
        required property var modelData
        toplevel: modelData
        window: list.window
        tooltip: list.tooltip
        width: ListView.view.width
    }

    add: Transition {
        NumberAnimation { property: "scale"; from: 0.5; to: 1; duration: Theme.animNormal; easing.type: Easing.OutBack }
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.animFast }
    }
    remove: Transition {
        NumberAnimation { property: "scale"; to: 0.5; duration: Theme.animFast }
        NumberAnimation { property: "opacity"; to: 0; duration: Theme.animFast }
    }
    displaced: Transition {
        NumberAnimation { property: "y"; duration: Theme.animNormal; easing.type: Easing.OutCubic }
    }
}
