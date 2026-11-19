import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import Quickshell.Widgets

// Громкость основного выхода: колесо — громче/тише, клик — раздел «Звук»
// панели управления, средняя кнопка — без звука.
BarButton {
    id: root
    required property string screenName
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property bool ready: sink !== null && sink.audio !== null
    readonly property real volume: ready ? sink.audio.volume : 0
    readonly property bool muted: ready && sink.audio.muted

    hint: !ready ? "Нет звука" : muted ? "Звук выключен" : "Громкость " + Math.round(volume * 100) + "%"

    PwObjectTracker { objects: [root.sink] }

    active: ShellState.controlShows(screenName, "sound")
    onClicked: event => {
        if (event.button === Qt.MiddleButton) { if (ready) sink.audio.muted = !sink.audio.muted; }
        else { if (tooltip) tooltip.hide(); ShellState.toggleControl(screenName, "sound"); }
    }
    onWheel: event => {
        if (!ready) return;
        const step = event.angleDelta.y > 0 ? 0.05 : -0.05;
        sink.audio.volume = Math.max(0, Math.min(1, Math.round((volume + step) * 20) / 20));
        OsdState.progress("volume", "", Math.round(sink.audio.volume * 100), 100, "");
    }

    IconImage {
        anchors.centerIn: parent
        implicitSize: 20
        source: Icons.path(
            !root.ready || root.muted ? "audio-volume-muted"
            : root.volume < 0.34 ? "audio-volume-low"
            : root.volume < 0.67 ? "audio-volume-medium"
            : "audio-volume-high")
    }
}
