import QtQuick

// Текст: Onest нужной насыщенности (ось wght — font.weight её не меняет).
Text {
    property int size: 14
    property int weight: 400

    font.family: Theme.fontFamily
    font.pixelSize: size
    font.variableAxes: ({ "wght": weight })
    color: Theme.ink
}
