import QtQuick
import Quickshell
import Quickshell.Widgets

// Меню по правому клику на рабочем столе (Wallpaper.qml), как в Windows.
// Параметры открываются через open-settings: без «Параметров» Sedmio —
// раздел параметров KDE.
PopupWindow {
    id: menu
    required property var window

    readonly property var items: [
        { icon: "preferences-desktop-wallpaper", text: "Сменить обои", command: ["/usr/lib/sedmio/open-settings", "wallpaper"] },
        { icon: "preferences-desktop-display", text: "Параметры экрана", command: ["/usr/lib/sedmio/open-settings", "display", "kcm_kscreen"] },
        { icon: "utilities-terminal", text: "Терминал", command: ["konsole"] },
        { icon: "preferences-system", text: "Параметры", command: ["/usr/lib/sedmio/open-settings"] },
    ]

    function openAt(x, y) {
        ShellState.closeAll();
        anchor.rect.x = x;
        anchor.rect.y = y;
        visible = true;
        keys.forceActiveFocus();
    }

    function run(command) {
        visible = false;
        Quickshell.execDetached(command);
    }

    anchor.window: window
    anchor.rect.width: 1
    anchor.rect.height: 1
    anchor.edges: Edges.Bottom | Edges.Right
    anchor.gravity: Edges.Bottom | Edges.Right
    grabFocus: true
    color: "transparent"
    implicitWidth: 240
    implicitHeight: rows.implicitHeight + 12
    visible: false

    Rectangle {
        id: keys
        anchors.fill: parent
        radius: 12
        color: Theme.surface
        border.width: 1
        border.color: Theme.line
        focus: true
        Keys.onEscapePressed: menu.visible = false

        Column {
            id: rows
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 6 }
            spacing: 2

            Repeater {
                model: menu.items

                Rectangle {
                    id: row
                    required property var modelData
                    width: rows.width
                    height: 36
                    radius: 8
                    color: rowArea.containsMouse ? Theme.paperDeep : "transparent"
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }

                    IconImage {
                        id: rowIcon
                        anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                        implicitSize: 18
                        source: Quickshell.iconPath(row.modelData.icon, true)
                    }
                    SText {
                        anchors { left: rowIcon.right; leftMargin: 10; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                        elide: Text.ElideRight
                        size: 13
                        text: row.modelData.text
                    }
                    MouseArea {
                        id: rowArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: menu.run(row.modelData.command)
                    }
                }
            }
        }
    }
}
