import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Sedmio.Style

// Всплывающее меню. Пункты — список объектов:
//   { text, icon, shortcut, enabled, checked, action: function, items: [...] }
//   { separator: true }
// items — вложенное меню (открывается при наведении).
Popup {
    id: menu
    property var items: []
    // Выбрали пункт (в том числе во вложенном меню).
    signal triggered()

    parent: Overlay.overlay
    padding: 6
    margins: 8
    modal: false
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent | Popup.CloseOnPressOutside

    function openAt(item, px, py) {
        const p = item.mapToItem(Overlay.overlay, px, py);
        x = p.x;
        y = p.y;
        open();
    }

    enter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.animFast } }
    exit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 90 } }

    background: Rectangle {
        implicitWidth: 262
        radius: 12
        color: Theme.surface
        border.width: 1
        border.color: Theme.line
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Theme.shadow
            shadowOpacity: 0.18
            shadowBlur: 0.6
            shadowVerticalOffset: 3
        }
    }

    contentItem: Column {
        id: column
        width: 250

        Repeater {
            model: menu.items

            Loader {
                id: entry
                required property var modelData
                width: column.width
                sourceComponent: modelData.separator ? separator : row
            }
        }
    }

    Component {
        id: separator
        Item {
            height: 9
            Rectangle {
                anchors.centerIn: parent
                width: parent.width - 16
                height: 1
                color: Theme.line
            }
        }
    }

    Component {
        id: row
        Rectangle {
            id: menuRow
            readonly property var data_: parent.modelData
            readonly property bool enabled_: data_.enabled !== false
            readonly property bool hasSub: (data_.items ?? []).length > 0

            height: 34
            radius: 8
            color: area.containsMouse && enabled_ ? Theme.greenWash : "transparent"
            opacity: enabled_ ? 1 : 0.4

            SIcon {
                id: icon
                anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                name: menuRow.data_.checked === true ? "checkmark" : (menuRow.data_.icon ?? "")
                size: 16
            }
            SText {
                id: label
                anchors { left: parent.left; leftMargin: 36; verticalCenter: parent.verticalCenter }
                text: menuRow.data_.text ?? ""
            }
            SText {
                id: shortcut
                anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                text: menuRow.hasSub ? "›" : (menuRow.data_.shortcut ?? "")
                size: Theme.fontSmall
                color: Theme.inkMuted
            }

            MouseArea {
                id: area
                anchors.fill: parent
                hoverEnabled: true
                onContainsMouseChanged: {
                    if (containsMouse && menuRow.hasSub && menuRow.enabled_) sub.active = true;
                }
                onClicked: {
                    if (!menuRow.enabled_) return;
                    if (menuRow.hasSub) {
                        sub.active = true;
                        return;
                    }
                    menu.close();
                    menu.triggered();
                    if (menuRow.data_.action) menuRow.data_.action();
                }
            }

            // Вложенное меню справа от пункта
            Loader {
                id: sub
                active: false
                source: "Menu.qml"
                onLoaded: {
                    sub.item.items = menuRow.data_.items;
                    sub.item.openAt(menuRow, menuRow.width - 4, -6);
                    sub.item.closed.connect(() => sub.active = false);
                    sub.item.triggered.connect(() => {
                        menu.close();
                        menu.triggered();
                    });
                }
            }
        }
    }
}
