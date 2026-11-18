import QtQuick

// Фон — как обои оболочки (sedmio-shell, Wallpaper.qml): мягкий
// градиент и знак Sedmio в углу.
Rectangle {
    id: root
    gradient: Gradient {
        GradientStop { position: 0.0; color: "#E8EDE3" }
        GradientStop { position: 0.55; color: "#D6E1D0" }
        GradientStop { position: 1.0; color: "#B9CCB3" }
    }

    Image {
        readonly property int size: Math.min(root.width, root.height) * 0.36
        width: size
        height: size
        sourceSize: Qt.size(size, size)
        anchors { right: parent.right; bottom: parent.bottom; rightMargin: root.width * 0.08; bottomMargin: root.height * 0.1 }
        source: "file:///usr/share/icons/hicolor/scalable/apps/sedmio.svg"
        opacity: 0.13
    }
}
