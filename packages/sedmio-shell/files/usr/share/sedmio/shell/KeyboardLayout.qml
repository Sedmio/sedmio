import QtQuick
import Quickshell.Services.Kde
import Sedmio.Style

// Текущая раскладка из KWin — как в Windows: ENG, РУС. Клик — следующая.
// Видна, только если раскладок больше одной.
BarButton {
    id: root
    readonly property var layout: KeyboardLayouts.current
    // Подписи языков, как на панели Windows; остальные — кодом раскладки (DE).
    readonly property var windowsLabels: ({
        "us": "ENG", "gb": "ENG", "au": "ENG", "ie": "ENG",
        "ru": "РУС", "ua": "УКР", "by": "БЕЛ", "kz": "КАЗ"
    })
    // Свою подпись (kxkbrc, DisplayNames) пользователь задал сам — она главнее.
    readonly property string label: layout.displayName
        || windowsLabels[layout.shortName || ""]
        || (layout.shortName || "").toUpperCase()

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
