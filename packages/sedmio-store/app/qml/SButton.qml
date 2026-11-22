// Копия из sedmio-preferences (app/qml): «Программы» — отдельный пакет:
// общего модуля оформления пока нет.
// Меняя оформление, менять во всех копиях (и в sedmio-tasks).
import QtQuick
import Sedmio.Style

// Кнопка с текстом. primary — зелёная, danger — терракотовая.
Rectangle {
    id: root
    property string text
    property bool primary: false
    property bool danger: false
    signal clicked()

    implicitWidth: label.implicitWidth + 28
    implicitHeight: 34
    radius: 10
    color: danger ? (area.containsMouse ? Qt.darker(Theme.terracotta, 1.08) : Theme.terracotta)
         : primary ? (area.containsMouse ? Qt.lighter(Theme.green, 1.12) : Theme.green)
         : (area.containsMouse ? Theme.paper : Theme.surface)
    border.width: primary || danger ? 0 : 1
    border.color: Theme.line
    Behavior on color { ColorAnimation { duration: Theme.animFast } }

    SText {
        id: label
        anchors.centerIn: parent
        text: root.text
        size: 13
        weight: 600
        color: root.primary || root.danger ? Theme.textOnGreen : Theme.ink
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.clicked()
    }
}
