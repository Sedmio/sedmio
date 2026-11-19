import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Sedmio.Style

// Выпадающий список: model — массив строк, currentIndex — выбранная.
// activated(index) — выбрали другую строку (сам currentIndex не меняет:
// значение приходит обратно из движка).
Rectangle {
    id: root
    property var model: []
    property int currentIndex: -1
    property bool enabled_: true
    signal activated(int index)

    implicitWidth: 260
    implicitHeight: 34
    radius: 10
    opacity: enabled_ ? 1 : 0.45
    color: area.containsMouse && enabled_ ? Theme.paper : Theme.surface
    border.width: 1
    border.color: popup.opened ? Theme.green : Theme.line
    Behavior on color { ColorAnimation { duration: Theme.animFast } }

    SText {
        anchors { left: parent.left; leftMargin: 12; right: arrow.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
        text: root.currentIndex >= 0 && root.currentIndex < root.model.length ? root.model[root.currentIndex] : "—"
        elide: Text.ElideRight
    }

    SIcon {
        id: arrow
        anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
        name: "arrow-down"
        size: 16
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        onClicked: if (root.enabled_) popup.open()
    }

    Popup {
        id: popup
        y: root.height + 4
        width: root.width
        height: Math.min(list.contentHeight + 12, 320)
        padding: 6
        // У нижнего края окна — сдвинуть вверх, а не обрезать.
        margins: 8
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        onOpened: list.positionViewAtIndex(Math.max(0, root.currentIndex), ListView.Contain)

        background: Rectangle {
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

        contentItem: ListView {
            id: list
            clip: true
            model: root.model
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            delegate: Rectangle {
                required property int index
                required property string modelData
                width: list.width
                height: 32
                radius: 8
                color: index === root.currentIndex ? Theme.greenWash
                     : rowArea.containsMouse ? Theme.paperDeep : "transparent"
                SText {
                    anchors { left: parent.left; leftMargin: 10; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    text: parent.modelData
                    elide: Text.ElideRight
                    weight: parent.index === root.currentIndex ? 600 : 400
                }
                MouseArea {
                    id: rowArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        popup.close();
                        if (parent.index !== root.currentIndex) root.activated(parent.index);
                    }
                }
            }
        }
    }
}
