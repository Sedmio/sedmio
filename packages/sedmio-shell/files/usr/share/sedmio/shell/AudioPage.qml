import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import Sedmio.Style

// Страница «Звук»: куда выводить звук и откуда брать микрофон.
ColumnLayout {
    id: page
    property real maxHeight: 600
    signal back()
    signal openExternal(var command)

    readonly property var nodes: Pipewire.nodes.values.filter(n => n.audio && !n.isStream)
    readonly property var sinks: nodes.filter(n => n.isSink)
    readonly property var sources: nodes.filter(n => !n.isSink)

    spacing: 10

    function nodeName(node) {
        return node.description || node.nickname || node.name;
    }

    PageHeader {
        Layout.fillWidth: true
        title: "Звук"
        onBack: page.back()
    }

    Flickable {
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(contentHeight, Math.max(160, page.maxHeight - 160))
        contentHeight: lists.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: lists
            width: parent.width
            spacing: 2

            SText {
                Layout.leftMargin: 12
                text: "Вывод"
                size: Theme.fontSmall
                weight: 600
                color: Theme.inkMuted
            }

            SText {
                Layout.leftMargin: 12
                visible: page.sinks.length === 0
                text: "Устройств вывода нет"
                color: Theme.inkMuted
                size: 13
            }

            Repeater {
                model: ScriptModel { values: page.sinks }
                ListRow {
                    required property var modelData
                    Layout.fillWidth: true
                    icon: "audio-speakers"
                    title: page.nodeName(modelData)
                    selected: Pipewire.defaultAudioSink === modelData
                    trailingIcon: selected ? "checkmark" : ""
                    onClicked: Pipewire.preferredDefaultAudioSink = modelData
                }
            }

            SText {
                Layout.leftMargin: 12
                Layout.topMargin: 8
                visible: page.sources.length > 0
                text: "Микрофон"
                size: Theme.fontSmall
                weight: 600
                color: Theme.inkMuted
            }

            Repeater {
                model: ScriptModel { values: page.sources }
                ListRow {
                    required property var modelData
                    Layout.fillWidth: true
                    icon: "audio-input-microphone"
                    title: page.nodeName(modelData)
                    selected: Pipewire.defaultAudioSource === modelData
                    trailingIcon: selected ? "checkmark" : ""
                    onClicked: Pipewire.preferredDefaultAudioSource = modelData
                }
            }
        }
    }

    ListRow {
        Layout.fillWidth: true
        icon: "configure"
        title: "Параметры звука"
        onClicked: page.openExternal(["/usr/lib/sedmio/open-settings", "sound", "kcm_pulseaudio"])
    }
}
