import QtQuick
import Quickshell
import Quickshell.Wayland
import Sedmio.Style

// Индикатор громкости и яркости поверх полноэкранного окна (видео, игра).
// Обычный индикатор выезжает из рамки, а рамка тогда под окном — здесь
// отдельная плашка внизу экрана на слое Overlay. Мышь проходит насквозь,
// фокус клавиатуры не берёт.
PanelWindow {
    id: root

    readonly property bool fullscreenHere: {
        const active = ToplevelManager.activeToplevel;
        return !!active && active.fullscreen && active.screens.some(s => s.name === root.screen.name);
    }

    visible: fullscreenHere && OsdState.shown && OsdState.screenName === screen.name
    anchors.bottom: true
    margins.bottom: 56
    implicitWidth: osd.wantedWidth
    implicitHeight: 54
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    mask: Region {}
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "sedmio-osd"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Theme.surface
        border.width: 1
        border.color: Theme.line

        Osd {
            id: osd
            anchors.fill: parent
        }
    }
}
