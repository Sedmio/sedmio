// Копия из sedmio-preferences (app/qml): диспетчер задач — отдельный пакет,
// чтобы сломанное обновление «Параметров» не задело инструмент спасения.
// Меняя оформление, менять в обоих местах.
import QtQuick

// Значок из темы по имени. Мелкие значки Breeze нарисованы под 16 и 22
// пикселя — берём ровно свой размер, иначе тонкие линии при сжатии рвутся.
Image {
    property string name
    property int size: 20

    width: size
    height: size
    sourceSize: Qt.size(size * Screen.devicePixelRatio, size * Screen.devicePixelRatio)
    source: name === "" ? "" : "image://icon/" + name
    smooth: true
}
