import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import Quickshell.Widgets

// Громкость основного выхода: колесо — громче/тише, клик — без звука.
BarButton {
    id: root
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property bool ready: sink !== null && sink.audio !== null
    readonly property real volume: ready ? sink.audio.volume : 0
    readonly property bool muted: ready && sink.audio.muted

    hint: !ready ? "Нет звука" : muted ? "Звук выключен" : "Громкость " + Math.round(volume * 100) + "%"

    PwObjectTracker { objects: [root.sink] }

    onClicked: if (ready) sink.audio.muted = !sink.audio.muted
    onWheel: event => {
        if (!ready) return;
        const step = event.angleDelta.y > 0 ? 0.05 : -0.05;
        sink.audio.volume = Math.max(0, Math.min(1, Math.round((volume + step) * 20) / 20));
    }

    IconImage {
        anchors.centerIn: parent
        implicitSize: 20
        source: Quickshell.iconPath(
            !root.ready || root.muted ? "audio-volume-muted"
            : root.volume < 0.34 ? "audio-volume-low"
            : root.volume < 0.67 ? "audio-volume-medium"
            : "audio-volume-high")
    }
}
