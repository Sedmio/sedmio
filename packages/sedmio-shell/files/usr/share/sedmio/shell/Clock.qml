import QtQuick
import Quickshell

// Часы столбиком: часы над минутами. Дата — в подсказке.
BarButton {
    id: root
    implicitHeight: column.implicitHeight + 12
    hint: clock.date.toLocaleDateString(Qt.locale(), "dddd, d MMMM")

    SystemClock { id: clock; precision: SystemClock.Minutes }

    Column {
        id: column
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
}
