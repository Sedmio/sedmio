pragma Singleton
import QtQuick

// Палитра и шрифт — те же, что в оболочке (sedmio-shell, Theme.qml)
// и установщике. Здесь только то, что нужно экранам входа и блокировки.
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
    readonly property color textOnGreen: "#F4F7F1"

    readonly property color terracotta: "#C8643B"
    readonly property color terracottaSoft: "#F0D8C8"

    readonly property int animFast: 120
    readonly property int animNormal: 220

    // Значки Breeze рисуют тёмным — подходят к светлому фону.
    function icon(name) { return "file:///usr/share/icons/breeze/actions/22/" + name + ".svg"; }
}
