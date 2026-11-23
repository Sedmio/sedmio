// Копия из sedmio-preferences (app/qml): «Программы» — отдельный пакет:
// общего модуля оформления пока нет.
// Меняя оформление, менять во всех копиях (и в sedmio-tasks).
import QtQuick
import Sedmio.Style

// Значок из темы по имени. Мелкие значки Breeze нарисованы под 16 и 22
// пикселя — берём ровно свой размер, иначе тонкие линии при сжатии рвутся.
// Цвет значков KDE берёт из палитры: она сменилась (другая тема) — значок
// перезапрашивается (?palette=, провайдер это отрезает).
//
// symbolic: true — однотонный символ (Sedmio.Style Symbols) цвета color,
// если для этого имени он есть: для кнопок, меню и боковых панелей. Значки
// программ и файлов — без него.
Image {
    property string name
    property int size: 20
    property bool symbolic: false
    property color color: Theme.inkSoft
    readonly property bool asSymbol: symbolic && Symbols.has(name)

    width: size
    height: size
    sourceSize: Qt.size(size * Screen.devicePixelRatio, size * Screen.devicePixelRatio)
    source: name === "" ? ""
          : asSymbol ? Symbols.url(name, color, size)
          : "image://icon/" + name + "?palette=" + Theme.paletteSerial
    smooth: true
}
