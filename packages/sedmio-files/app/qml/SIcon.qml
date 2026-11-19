import QtQuick
import Sedmio.Style

// Значок из темы по имени. Мелкие значки Breeze нарисованы под 16 и 22
// пикселя — берём ровно свой размер, иначе тонкие линии при сжатии рвутся.
// Цвет значков KDE берёт из палитры: она сменилась (другая тема) — значок
// перезапрашивается (?palette=, провайдер это отрезает).
Image {
    property string name
    property int size: 20

    width: size
    height: size
    sourceSize: Qt.size(size * Screen.devicePixelRatio, size * Screen.devicePixelRatio)
    source: name === "" ? "" : "image://icon/" + name + "?palette=" + Theme.paletteSerial
    smooth: true
}
