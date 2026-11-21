import QtQuick
import Sedmio.Style

// Подсказка у кнопки панели (название окна, громкость, дата): справа от
// полосы слева, под верхней панелью, над нижней — смотря где кнопка.
// Одна на экран; кнопки панели вызывают show() и hide().
Rectangle {
    id: tip
    property string text
    // Кнопка в координатах окна рамки.
    property rect target
    property bool shown: false
    property Item owner

    function show(text, item) {
        const p = item.mapToItem(null, 0, 0);
        tip.text = text;
        tip.target = Qt.rect(p.x, p.y, item.width, item.height);
        tip.owner = item;
        tip.shown = true;
    }

    // hide(item) гасит подсказку, только если она этой кнопки: при переходе
    // на соседнюю кнопку «вход» в неё может прийти раньше «выхода» из старой.
    function hide(item) {
        if (item === undefined || item === tip.owner)
            tip.shown = false;
    }

    readonly property real windowWidth: parent ? parent.width : 0
    readonly property real windowHeight: parent ? parent.height : 0
    // С какой стороны кнопки: "right" (полоса слева), "below", "above".
    readonly property string side: DesktopLayout.left && target.x < Theme.barWidth ? "right"
        : target.y + target.height / 2 < windowHeight / 2 ? "below" : "above"

    x: side === "right" ? Theme.barWidth + 8
        : Math.round(Math.max(6, Math.min(windowWidth - width - 6, target.x + target.width / 2 - width / 2)))
    y: side === "right" ? Math.round(target.y + target.height / 2 - height / 2)
        : side === "below" ? Math.round(target.y + target.height + 8)
        : Math.round(target.y - height - 8)
    width: Math.min(label.implicitWidth + 24, 420)
    height: 32
    radius: 10
    color: Theme.ink
    opacity: shown && text !== "" ? 1 : 0
    visible: opacity > 0

    Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
    // Между соседними кнопками подсказка переезжает, а не мигает.
    Behavior on y {
        enabled: tip.visible && tip.side === "right"
        NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic }
    }
    Behavior on x {
        enabled: tip.visible && tip.side !== "right"
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
