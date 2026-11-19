import QtQuick
import Sedmio.Style

// Квадратная кнопка панели со скруглением: подсветка при наведении,
// подсказка справа. Содержимое кладётся внутрь.
Rectangle {
    id: button
    property Item tooltip
    property string hint
    property bool active: false
    readonly property alias hovered: mouse.containsMouse

    signal clicked(var mouse)
    signal wheel(var wheel)

    implicitWidth: Theme.buttonSize
    implicitHeight: Theme.buttonSize
    radius: Theme.radius
    // Не "transparent": это прозрачный чёрный, и переход от него к
    // светлому на полпути даёт тёмную вспышку. Прозрачный — того же тона.
    color: active ? Theme.greenWash : (hovered ? Theme.paperDeep : Qt.alpha(Theme.paperDeep, 0))
    Behavior on color { ColorAnimation { duration: Theme.animFast } }

    function showHint() {
        if (tooltip && hint !== "")
            tooltip.show(hint, mapToItem(null, 0, height / 2).y);
    }

    onHintChanged: if (hovered) showHint()

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        onClicked: event => button.clicked(event)
        onWheel: event => button.wheel(event)
        onContainsMouseChanged: {
            if (containsMouse) button.showHint();
            else if (button.tooltip) button.tooltip.hide();
        }
    }
}
