import QtQuick

// Заголовок страницы: маленькая метка шага, крупный плотный заголовок,
// спокойный подзаголовок.
Column {
    id: root

    property string eyebrow: ""
    property string title: ""
    property string subtitle: ""

    spacing: 14

    Text {
        visible: root.eyebrow !== ""
        text: root.eyebrow
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSmall
        font.weight: Font.DemiBold
        font.letterSpacing: 1.2
        font.capitalization: Font.AllUppercase
        color: Theme.terracotta
    }

    Text {
        width: root.width
        text: root.title
        wrapMode: Text.WordWrap
        lineHeight: 1.02
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontTitle
        font.weight: Font.DemiBold
        font.letterSpacing: Theme.titleTracking
        color: Theme.ink
    }

    Text {
        visible: root.subtitle !== ""
        width: root.width
        text: root.subtitle
        wrapMode: Text.WordWrap
        lineHeight: 1.3
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontLarge
        color: Theme.inkSoft
    }
}
