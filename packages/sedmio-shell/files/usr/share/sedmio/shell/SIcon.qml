import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets
import Sedmio.Style

// Значок из темы. light: true — перекрасить в светлый (на зелёном фоне).
// symbolic: true — однотонный символ (Sedmio.Style Symbols) цвета color,
// если для этого имени он есть: кнопки, меню, плитки. Значки программ
// (панель задач, «Пуск») — без него.
IconImage {
    id: root
    property string name
    property string fallback: "image-missing"
    property bool light: false
    property bool symbolic: false
    property color color: light ? Theme.textOnGreen : Theme.inkSoft
    readonly property bool asSymbol: symbolic && Symbols.has(name)

    implicitSize: 20
    source: name === "" ? "" : asSymbol ? Symbols.url(name, color, implicitSize) : Icons.path(name, fallback)

    layer.enabled: light && !asSymbol
    layer.effect: MultiEffect {
        brightness: 1.0
    }
}
