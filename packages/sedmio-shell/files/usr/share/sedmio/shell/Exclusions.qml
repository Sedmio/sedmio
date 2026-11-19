import QtQuick
import Quickshell
import Quickshell.Wayland
import Sedmio.Style

// Невидимые полосы по краям экрана. Сама рамка (Frame) занимает весь
// экран и место не резервирует, а эти полосы резервируют: развёрнутые
// окна встают внутрь рамки, а не под неё.
Scope {
    id: root
    required property var screen

    component Edge: PanelWindow {
        screen: root.screen
        color: "transparent"
        implicitWidth: 1
        implicitHeight: 1
        mask: Region {}   // мышь проходит насквозь
        WlrLayershell.namespace: "sedmio-exclusion"
    }

    Edge { anchors { left: true; top: true; bottom: true } exclusiveZone: Theme.barWidth }
    Edge { anchors { top: true; left: true; right: true } exclusiveZone: Theme.border }
    Edge { anchors { right: true; top: true; bottom: true } exclusiveZone: Theme.border }
    Edge { anchors { bottom: true; left: true; right: true } exclusiveZone: Theme.border }
}
