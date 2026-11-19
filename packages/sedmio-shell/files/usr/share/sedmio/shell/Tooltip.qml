import QtQuick
import Sedmio.Style

// Подсказка справа от панели (название окна, громкость, дата).
// Одна на экран; кнопки панели вызывают show() и hide().
Rectangle {
    id: tip
    property string text
    property real anchorY      // середина кнопки, в координатах окна рамки
    property bool shown: false

    function show(text, anchorY) {
        tip.text = text;
        tip.anchorY = anchorY;
        tip.shown = true;
    }

    function hide() { tip.shown = false; }

    x: Theme.barWidth + 8
    y: Math.round(anchorY - height / 2)
    width: Math.min(label.implicitWidth + 24, 420)
    height: 32
    radius: 10
    color: Theme.ink
    opacity: shown && text !== "" ? 1 : 0
    visible: opacity > 0

    Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
    // Между соседними кнопками подсказка переезжает, а не мигает.
    Behavior on y {
        enabled: tip.visible
        NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic }
    }

    SText {
        id: label
        anchors.verticalCenter: parent.verticalCenter
        x: 12
        width: tip.width - 24
        elide: Text.ElideRight
        text: tip.text
        color: Theme.textOnGreen
        size: 13
        weight: 500
    }
}
