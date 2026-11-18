import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets

// Значок из темы. light: true — перекрасить в светлый (на зелёном фоне).
IconImage {
    id: root
    property string name
    property string fallback: "image-missing"
    property bool light: false

    implicitSize: 20
    source: name === "" ? "" : Quickshell.iconPath(name, fallback)

    layer.enabled: light
    layer.effect: MultiEffect {
        brightness: 1.0
    }
}
