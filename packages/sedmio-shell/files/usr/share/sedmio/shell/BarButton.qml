import QtQuick
import Sedmio.Style

// Квадратная кнопка панели со скруглением: подсветка при наведении,
// подсказка у кнопки (Tooltip). Содержимое кладётся внутрь.
Rectangle {
    id: button
    property Item tooltip
    property string hint
    property bool active: false
    // Сторона кнопки; панель задаёт её по своей толщине. Значки внутри —
    // iconSize.
    property real size: Theme.buttonSize
    readonly property int iconSize: Math.round(size * 20 / 36)
    readonly property alias hovered: mouse.containsMouse

    signal clicked(var mouse)
    signal wheel(var wheel)

    implicitWidth: size
    implicitHeight: size
    radius: Theme.radius
    // Не "transparent": это прозрачный чёрный, и переход от него к
    // светлому на полпути даёт тёмную вспышку. Прозрачный — того же тона.
    color: active ? Theme.greenWash : (hovered ? Theme.paperDeep : Qt.alpha(Theme.paperDeep, 0))
    Behavior on color { ColorAnimation { duration: Theme.animFast } }

    function showHint() {
        if (tooltip && hint !== "")
            tooltip.show(hint, button);
    }

    // Подсказка стала пустой (у панели задач — когда окно одно) — убрать.
    onHintChanged: {
        if (!hovered) return;
        if (hint !== "") showHint();
        else if (tooltip) tooltip.hide(button);
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        onClicked: event => button.clicked(event)
        onWheel: event => button.wheel(event)
        onContainsMouseChanged: {
            if (containsMouse) button.showHint();
            else if (button.tooltip) button.tooltip.hide(button);
        }
    }
}
