import QtQuick
import qs
import QtQuick.Shapes
import Sedmio.Style

// Колокольчик: клик — центр уведомлений, средняя кнопка — «Не беспокоить».
// Точка — пришли новые, пока центр не открывали. Пока программы копируют
// файлы, вокруг колокольчика кольцо их общего хода.
BarButton {
    id: root
    readonly property int unread: NotificationState.unread
    readonly property int count: NotificationState.history.length
    readonly property var running: JobsState.running

    active: ShellState.notificationsScreen === screenName
    hint: {
        if (running.length === 1)
            return (running[0].title || "Операция") + ": " + running[0].percent + "%";
        if (running.length > 1)
            return running.length + " " + JobsState.plural(running.length, "операция", "операции", "операций")
                + ": " + JobsState.percent + "%";
        return (NotificationState.doNotDisturb ? "Не беспокоить · " : "")
            + (count === 0 ? "Нет уведомлений" : "Уведомления: " + count);
    }

    onClicked: event => {
        if (event.button === Qt.MiddleButton) {
            NotificationState.setDoNotDisturb(!NotificationState.doNotDisturb);
        } else {
            if (tooltip) tooltip.hide();
            ShellState.toggleNotifications(screenName);
        }
    }

    SIcon {
        anchors.centerIn: parent
        implicitSize: root.running.length > 0 ? Math.round(root.iconSize * 0.8) : root.iconSize
        Behavior on implicitSize { NumberAnimation { duration: Theme.animFast } }
        name: NotificationState.doNotDisturb ? "notifications-disabled" : "notifications"
        symbolic: true
        color: Theme.ink
    }

    // Кольцо хода операций
    Shape {
        id: ring
        anchors.centerIn: parent
        width: 28
        height: 28
        visible: opacity > 0
        opacity: root.running.length > 0 ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.animNormal } }
        preferredRendererType: Shape.CurveRenderer

        property real progress: JobsState.percent / 100
        Behavior on progress { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }

        ShapePath {
            fillColor: "transparent"
            strokeColor: Theme.line
            strokeWidth: 2.5
            PathAngleArc { centerX: 14; centerY: 14; radiusX: 12.5; radiusY: 12.5; startAngle: 0; sweepAngle: 360 }
        }
        ShapePath {
            fillColor: "transparent"
            strokeColor: Theme.green
            strokeWidth: 2.5
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: 14; centerY: 14; radiusX: 12.5; radiusY: 12.5
                startAngle: -90
                sweepAngle: 360 * ring.progress
            }
        }
    }

    Rectangle {
        visible: root.unread > 0
        x: parent.width / 2 + 3
        y: parent.height / 2 - 10
        width: 9
        height: 9
        radius: 4.5
        color: Theme.terracotta
        border.width: 2
        border.color: Theme.paper
    }
}
