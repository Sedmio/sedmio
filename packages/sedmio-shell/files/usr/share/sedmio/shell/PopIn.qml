import QtQuick
import Sedmio.Style

// Появление всплывающей карточки (меню, список окон, миниатюры): из чуть
// меньшей и прозрачной — на место, с пружинкой. Перелёт маленький:
// карточка не вылезает за своё окно. Запускать restart() при показе;
// откуда растёт — card.transformOrigin.
ParallelAnimation {
    id: root
    required property Item card

    NumberAnimation {
        target: root.card
        property: "scale"
        from: 0.94
        to: 1
        duration: Motion.springDuration
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Motion.spring
    }
    NumberAnimation {
        target: root.card
        property: "opacity"
        from: 0
        to: 1
        duration: Theme.animFast
    }
}
