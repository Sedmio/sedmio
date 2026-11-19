import QtQuick

// Ползунок оболочки. value — от 0 до maximum; пока ползунок тянут, внешнее
// значение не перебивает палец. moved — новое значение от пользователя.
Item {
    id: root
    property real value: 0
    property real maximum: 1
    property real step: maximum / 20
    signal moved(real value)

    readonly property bool pressed: area.pressed
    property real dragValue: 0
    readonly property real shown: Math.max(0, Math.min(maximum, pressed ? dragValue : value))
    readonly property real fraction: maximum > 0 ? shown / maximum : 0

    implicitHeight: 28
    implicitWidth: 200

    function setFromX(x) {
        const usable = width - handle.width;
        const f = usable > 0 ? (x - handle.width / 2) / usable : 0;
        dragValue = Math.max(0, Math.min(1, f)) * maximum;
        moved(dragValue);
    }

    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 6
        radius: 3
        color: Theme.paperDeep

        Rectangle {
            width: handle.x + handle.width / 2
            height: parent.height
            radius: parent.radius
            color: Theme.green
        }
    }

    Rectangle {
        id: handle
        anchors.verticalCenter: parent.verticalCenter
        x: root.fraction * (root.width - width)
        width: 18
        height: 18
        radius: 9
        color: Theme.surface
        border.width: 2
        border.color: Theme.green
        scale: area.pressed ? 1.1 : (area.containsMouse ? 1.05 : 1)
        Behavior on scale { NumberAnimation { duration: Theme.animFast } }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        preventStealing: true
        onPressed: event => root.setFromX(event.x)
        onPositionChanged: event => { if (pressed) root.setFromX(event.x); }
        onWheel: event => {
            const delta = event.angleDelta.y > 0 ? root.step : -root.step;
            const next = Math.max(0, Math.min(root.maximum, root.value + delta));
            root.moved(Math.round(next / root.step) * root.step);
        }
    }
}
