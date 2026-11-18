import QtQuick
import Quickshell.Services.Kde

// Текущая раскладка (RU, US...) из KWin. Клик — следующая.
// Видна, только если раскладок больше одной.
BarButton {
    id: root
    readonly property var layout: KeyboardLayouts.current
    readonly property string label: (layout.displayName || layout.shortName || "").toUpperCase()

    visible: KeyboardLayouts.layouts.length > 1
    implicitHeight: 30
    hint: layout.longName || ""
    onClicked: KeyboardLayouts.switchToNext()
    onWheel: event => event.angleDelta.y > 0 ? KeyboardLayouts.switchToPrevious() : KeyboardLayouts.switchToNext()

    SText {
        anchors.centerIn: parent
        text: root.label
        size: 12
        weight: 650
        color: Theme.inkSoft
    }
}
