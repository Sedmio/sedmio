import QtQuick
import Quickshell
import Quickshell.Widgets
import Sedmio.Style

// Всплывающее меню: пункты {icon, text, action} и черты {separator: true}.
// Выбрали пункт — меню закрывается и шлёт triggered(action). Куда
// прикрепить (anchor) — задаёт тот, кто показывает. Стрелки выбирают,
// Enter — выполнить, Esc закрывает.
PopupWindow {
    id: menu
    property var items: []
    signal triggered(string action)

    // Выбранный пункт; -1 — никакой (открыли мышью и ещё не навели).
    property int current: -1

    function step(direction) {
        let i = current < 0 ? (direction > 0 ? -1 : items.length) : current;
        for (let n = 0; n < items.length; n++) {
            i = (i + direction + items.length) % items.length;
            if (!items[i].separator) { current = i; return; }
        }
    }

    function activate(index) {
        const item = items[index];
        if (!item || item.separator) return;
        visible = false;
        triggered(item.action);
    }

    grabFocus: true
    color: "transparent"
    implicitWidth: 260
    implicitHeight: rows.implicitHeight + 12
    visible: false

    onVisibleChanged: {
        current = -1;
        shown = visible ? signature() : "";
        if (visible) card.forceActiveFocus();
    }

    // Пункты поменялись, пока меню открыто (окно закрылось, программу
    // удалили) — закрыть: иначе меню сменит размер под курсором, а выбранный
    // номер укажет на другой пункт.
    property string shown: ""
    function signature() {
        return JSON.stringify(items.map(i => i.separator ? "-" : [i.icon, i.text, i.action]));
    }
    onItemsChanged: if (visible && signature() !== shown) visible = false

    Rectangle {
        id: card
        anchors.fill: parent
        radius: 12
        color: Theme.surface
        border.width: 1
        border.color: Theme.line
        focus: true
        Keys.onPressed: event => {
            switch (event.key) {
            case Qt.Key_Escape: menu.visible = false; break;
            case Qt.Key_Down: case Qt.Key_Tab: menu.step(1); break;
            case Qt.Key_Up: case Qt.Key_Backtab: menu.step(-1); break;
            case Qt.Key_Return: case Qt.Key_Enter: case Qt.Key_Space: menu.activate(menu.current); break;
            default: return;
            }
            event.accepted = true;
        }

        Column {
            id: rows
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 6 }
            spacing: 2

            Repeater {
                model: menu.items

                Item {
                    id: row
                    required property var modelData
                    required property int index
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
                        color: menu.current === row.index ? Theme.paperDeep : Qt.alpha(Theme.paperDeep, 0)
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
                            onContainsMouseChanged: if (containsMouse) menu.current = row.index
                            onClicked: menu.activate(row.index)
                        }
                    }
                }
            }
        }
    }
}
