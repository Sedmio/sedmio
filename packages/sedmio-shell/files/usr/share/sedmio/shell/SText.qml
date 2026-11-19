import QtQuick
import Sedmio.Style

// Текст оболочки: Onest нужной насыщенности.
Text {
    property int size: Theme.fontBody
    property int weight: 400

    font.family: Theme.fontFamily
    font.pixelSize: size
    font.variableAxes: ({ "wght": weight })
    color: Theme.ink
}
