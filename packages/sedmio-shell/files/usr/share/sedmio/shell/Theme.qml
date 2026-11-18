pragma Singleton
import QtQuick
import Quickshell

// Дизайн-система оболочки. Палитра та же, что в установщике
// (sedmio-calamares, components/Theme.qml): бумага, зелень седума,
// терракота. Все цвета, шрифты, размеры и движение — только здесь.
Singleton {
    // Onest ставит sedmio-branding. Вариативный шрифт: насыщенность
    // задаётся осью wght (SText.weight), font.weight на Linux её не меняет.
    readonly property string fontFamily: "Onest"

    // Бумага и поверхности
    readonly property color paper: "#EEF1EA"
    readonly property color paperDeep: "#E3E8DE"
    readonly property color surface: "#F8FAF5"
    readonly property color line: "#D5DCCF"
    readonly property color lineStrong: "#B7C2B0"

    // Текст
    readonly property color ink: "#1B251F"
    readonly property color inkSoft: "#4B5A50"
    readonly property color inkMuted: "#7E8A81"

    // Зелень: активное и главное
    readonly property color green: "#2F5D46"
    readonly property color greenWash: "#DCE7DA"
    readonly property color textOnGreen: "#F4F7F1"
    readonly property color leaf: "#6E9C74"
    readonly property color leafPale: "#D3E3CB"

    // Терракота: акценты и внимание
    readonly property color terracotta: "#C8643B"
    readonly property color terracottaSoft: "#F0D8C8"

    // Тень рамки на окнах
    readonly property color shadow: "#1D2420"

    // Типографика
    readonly property int fontSmall: 12
    readonly property int fontBody: 14
    readonly property int fontLarge: 15

    // Рамка и панель
    readonly property int barWidth: 48       // панель слева
    readonly property int border: 6          // рамка по остальным краям
    readonly property int frameRadius: 18    // скругление внутренних углов
    readonly property int buttonSize: 36
    readonly property int radius: 11

    // Движение
    readonly property int animFast: 140
    readonly property int animNormal: 260
}
