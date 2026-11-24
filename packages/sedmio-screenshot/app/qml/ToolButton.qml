import QtQuick
import QtQuick.Controls
import Sedmio.Style

// Кнопка-значок полосы инструментов. checked — выбранный инструмент.
Item {
    id: root
    property string icon
    property string hint
    property bool checked: false
    property bool enabled_: true
    signal clicked()

    implicitWidth: 36
    implicitHeight: 36
    opacity: enabled_ ? 1 : 0.4

    Rectangle {
        anchors.fill: parent
        radius: 10
        color: root.checked ? Theme.greenWash
             : area.containsMouse && root.enabled_ ? Theme.surface : Qt.alpha(Theme.surface, 0)
        border.width: root.checked ? 1 : 0
        border.color: Theme.green
        Behavior on color { ColorAnimation { duration: Theme.animFast } }
    }

    SIcon {
        anchors.centerIn: parent
        name: root.icon
        size: 18
        symbolic: true
        color: root.checked ? Theme.green : Theme.inkSoft
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        onClicked: if (root.enabled_) root.clicked()
    }

    // Подсказка снизу. Popup, а не дочерний прямоугольник: соседние
    // полосы рисуются позже кнопки и закрывали подсказку; Popup лежит над
    // всем окном, а margins не дают ему вылезти за края.
    Popup {
        visible: area.containsMouse && root.hint !== ""
        x: (root.width - width) / 2
        y: root.height + 6
        margins: 4
        padding: 0
        closePolicy: Popup.NoAutoClose
        enter: null
        exit: null
        background: Rectangle { radius: 7; color: Theme.ink }
        contentItem: SText {
            leftPadding: 8
            rightPadding: 8
            topPadding: 4
            bottomPadding: 4
            text: root.hint
            size: 12
            color: Theme.paper
        }
    }
}
