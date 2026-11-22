import QtQuick
import Sedmio.Style

// Значок программы из каталога: файл на диске (PNG Flathub, JPEG XL
// каталога Arch), по сети или из темы. Не открылся — общий значок.
Item {
    id: root
    property string source
    property int size: 48
    width: size
    height: size

    Image {
        id: image
        anchors.fill: parent
        source: root.source
        sourceSize: Qt.size(root.size * Screen.devicePixelRatio, root.size * Screen.devicePixelRatio)
        asynchronous: true
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
    }
    SIcon {
        anchors.fill: parent
        size: root.size
        visible: root.source === "" || image.status === Image.Error
        name: visible ? "application-x-executable" : ""
    }
}
