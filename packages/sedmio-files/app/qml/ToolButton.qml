import QtQuick
import Sedmio.Style

// Квадратная кнопка со значком: назад, вперёд, вид…
Rectangle {
    id: root
    property string icon
    property string hint
    property bool checked: false
    property bool enabled_: true
    signal clicked()

    implicitWidth: 34
    implicitHeight: 34
    radius: 10
    opacity: enabled_ ? 1 : 0.4
    color: checked ? Theme.greenWash : (area.containsMouse && enabled_ ? Theme.paperDeep : Qt.alpha(Theme.paperDeep, 0))
    Behavior on color { ColorAnimation { duration: Theme.animFast } }

    SIcon {
        anchors.centerIn: parent
        name: root.icon
        size: 18
        symbolic: true
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        onClicked: if (root.enabled_) root.clicked()
    }
}
