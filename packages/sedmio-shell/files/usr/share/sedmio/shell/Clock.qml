import QtQuick
import Quickshell
import Sedmio.Style

// Часы. В полосе слева — столбиком: часы над минутами, дата в подсказке.
// В верхней панели (wide) — строкой с датой: «Вс, 22 ноября  02:17».
// Клик — календарь.
BarButton {
    id: root
    required property string screenName
    property bool wide: false
    active: ShellState.controlShows(screenName, "calendar")
    onClicked: { if (tooltip) tooltip.hide(); ShellState.toggleControl(screenName, "calendar"); }
    implicitWidth: wide ? line.implicitWidth + 24 : size
    implicitHeight: wide ? size : column.implicitHeight + 12
    hint: wide ? "" : clock.date.toLocaleDateString(Qt.locale(), "dddd, d MMMM")

    SystemClock { id: clock; precision: SystemClock.Minutes }

    Column {
        id: column
        visible: !root.wide
        anchors.centerIn: parent
        spacing: -3

        SText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatTime(clock.date, "hh")
            size: Theme.fontLarge
            weight: 650
        }
        SText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatTime(clock.date, "mm")
            size: Theme.fontLarge
            weight: 450
            color: Theme.inkSoft
        }
    }

    Row {
        id: line
        visible: root.wide
        anchors.centerIn: parent
        spacing: 10

        SText {
            anchors.verticalCenter: parent.verticalCenter
            text: {
                const d = clock.date.toLocaleDateString(Qt.locale(), "ddd, d MMMM");
                return d.charAt(0).toUpperCase() + d.slice(1);
            }
            size: Theme.fontBody
            weight: 500
            color: Theme.inkSoft
        }
        SText {
            anchors.verticalCenter: parent.verticalCenter
            text: Qt.formatTime(clock.date, "hh:mm")
            size: Theme.fontLarge
            weight: 650
        }
    }
}
