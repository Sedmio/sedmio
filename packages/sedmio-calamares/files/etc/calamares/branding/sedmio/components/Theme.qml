pragma Singleton
import QtQuick

// Дизайн-система установщика: «живой, природный» стиль по мотивам седума.
// Все цвета, шрифты, размеры и параметры движения — только здесь.
QtObject {
    readonly property string productName: "Sedmio"

    // Шрифт Onest (вариативный, OFL) лежит рядом, в fonts/.
    readonly property FontLoader onest: FontLoader {
        source: Qt.resolvedUrl("../fonts/Onest-Variable.ttf")
    }
    readonly property string fontFamily: onest.status === FontLoader.Ready ? onest.font.family : "sans-serif"

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

    // Зелень: главный цвет действий
    readonly property color green: "#2F5D46"
    readonly property color greenHover: "#27503C"
    readonly property color greenPressed: "#1F4131"
    readonly property color greenWash: "#DCE7DA"
    readonly property color textOnGreen: "#F4F7F1"

    // Листья седума
    readonly property color leafDeep: "#355E47"
    readonly property color leaf: "#6E9C74"
    readonly property color leafLight: "#A8C59F"
    readonly property color leafPale: "#D3E3CB"

    // Терракота: румянец на кончиках листьев и акценты
    readonly property color terracotta: "#C8643B"
    readonly property color terracottaSoft: "#F0D8C8"
    readonly property color bloom: "#E8B04A"

    // ---------- Растение (Sedum, Leaf, Bloom, Logo)
    // Взрослый лист: от тени в глубине розетки к восковому светлому кончику
    readonly property color plantShade: "#173F3C"
    readonly property color plantDeep: "#2E6F62"
    readonly property color plantMid: "#5AA48E"
    readonly property color plantLight: "#99D2B8"
    readonly property color plantPale: "#CDEEDC"
    // Молодой лист в центре: свежая весенняя зелень
    readonly property color plantYoungShade: "#2A5E3F"
    readonly property color plantYoungDeep: "#4C8E57"
    readonly property color plantYoung: "#86C26F"
    readonly property color plantYoungLight: "#BEE28F"
    readonly property color plantYoungPale: "#E4F5B8"
    // Свет по краю листа, тень между листьями, румянец
    readonly property color plantGlow: "#F2FBDD"
    readonly property color plantShadow: "#0C2E2C"
    readonly property color plantBlushWarm: "#F6E2B8"
    readonly property color plantBlushSoft: "#F2A07E"
    readonly property color plantBlush: terracotta

    // Цветы: золотистые звёздочки на розоватых стеблях
    readonly property color flowerDeep: "#D29A35"
    readonly property color flower: "#EDBD52"
    readonly property color flowerLight: "#F9DE84"
    readonly property color flowerPale: "#FFF5C8"
    readonly property color flowerHeart: "#C7742A"
    readonly property color flowerAnther: "#B4532D"
    readonly property color flowerCarpel: "#CBD671"
    readonly property color flowerBud: "#D9873F"
    readonly property color flowerStalk: "#D38C78"
    readonly property color flowerStalkLight: "#EFBBA6"
    readonly property color flowerStalkDark: "#A65E4C"

    // Горшок и гравий
    readonly property color potLight: "#DE9A76"
    readonly property color potClay: "#CB7A54"
    readonly property color potDark: "#B4633F"
    readonly property color potDeep: "#8C4529"
    readonly property color gravelLight: "#EDE6D8"
    readonly property color gravel: "#D6CCBB"
    readonly property color gravelDark: "#B3A693"
    readonly property color groundShadow: "#1D2420"

    // Откуда падает свет на растение (вектор к источнику, экранные оси)
    readonly property real lightX: -0.55
    readonly property real lightY: -0.835

    // Состояния
    readonly property color success: "#4E8B5F"
    readonly property color warning: "#C4861C"
    readonly property color danger: "#B5462E"

    // Типографика
    readonly property int fontSmall: 13
    readonly property int fontBody: 15
    readonly property int fontLarge: 18
    readonly property int fontTitle: 44
    readonly property real titleTracking: -1.2

    // Размеры
    readonly property int radius: 14
    readonly property int radiusLarge: 20
    readonly property int controlHeight: 48
    readonly property int sideMargin: 72
    readonly property int contentWidth: 500

    // Движение: пружины вместо линейных анимаций
    readonly property int animFast: 140
    readonly property int animNormal: 260
    readonly property real springSoft: 2.2
    readonly property real dampingSoft: 0.28
    readonly property int stagger: 70
}
