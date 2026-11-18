pragma Singleton
import QtQuick

// Дизайн-система «Файлов» — та же, что у оболочки
// (sedmio-shell, Theme.qml): бумага, зелень седума, терракота, Onest.
QtObject {
    readonly property string fontFamily: "Onest"

    readonly property color paper: "#EEF1EA"
    readonly property color paperDeep: "#E3E8DE"
    readonly property color surface: "#F8FAF5"
    readonly property color line: "#D5DCCF"
    readonly property color lineStrong: "#B7C2B0"

    readonly property color ink: "#1B251F"
    readonly property color inkSoft: "#4B5A50"
    readonly property color inkMuted: "#7E8A81"

    readonly property color green: "#2F5D46"
    readonly property color greenWash: "#DCE7DA"
    readonly property color greenSelect: "#C9DCC8"
    readonly property color textOnGreen: "#F4F7F1"
    readonly property color leaf: "#6E9C74"

    readonly property color terracotta: "#C8643B"
    readonly property color terracottaSoft: "#F0D8C8"

    readonly property color shadow: "#1D2420"

    readonly property int fontSmall: 12
    readonly property int fontBody: 14

    readonly property int radius: 11

    readonly property int animFast: 140
    readonly property int animNormal: 260
}
