import QtQuick
import Quickshell
import Quickshell.Widgets
import Sedmio.Style

// Всплывающее меню: пункты {icon, text, action} и черты {separator: true}.
// Выбрали пункт — меню закрывается и шлёт triggered(action). Куда
// прикрепить (anchor) — задаёт тот, кто показывает. Esc закрывает.
PopupWindow {
    id: menu
    property var items: []
    signal triggered(string action)

    grabFocus: true
    color: "transparent"
    implicitWidth: 260
    implicitHeight: rows.implicitHeight + 12
    visible: false

    onVisibleChanged: if (visible) card.forceActiveFocus()

    Rectangle {
        id: card
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

                Item {
                    id: row
                    required property var modelData
                    width: rows.width
                    height: modelData.separator ? 9 : 36

                    Rectangle {
                        visible: !!row.modelData.separator
                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 8 }
                        height: 1
                        color: Theme.line
                    }

                    Rectangle {
                        visible: !row.modelData.separator
                        anchors.fill: parent
                        radius: 8
                        color: rowArea.containsMouse ? Theme.paperDeep : "transparent"
                        Behavior on color { ColorAnimation { duration: Theme.animFast } }

                        IconImage {
                            id: rowIcon
                            anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                            implicitSize: 18
                            source: row.modelData.icon ? Icons.path(row.modelData.icon, true) : ""
                        }
                        SText {
                            anchors { left: rowIcon.right; leftMargin: 10; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                            elide: Text.ElideRight
                            size: 13
                            text: row.modelData.text || ""
                        }
                        MouseArea {
                            id: rowArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                const action = row.modelData.action;
                                menu.visible = false;
                                menu.triggered(action);
                            }
                        }
                    }
                }
            }
        }
    }
}
