import QtQuick
import QtQuick.Effects

// Фон — как обои оболочки (sedmio-shell, Wallpaper.qml): мягкий
// градиент и знак Sedmio в углу.
//
// image — обои пользователя (экран блокировки и заставка работают от его
// имени; экран входа — нет, у него всегда градиент). Картинки нет или она
// не открылась — градиент. dimmed — размыть и высветлить под бумагу, чтобы
// часы и карточка читались на любой картинке.
Rectangle {
    id: root
    property url image: ""
    property bool dimmed: false

    readonly property bool hasImage: photo.status === Image.Ready

    gradient: Gradient {
        GradientStop { position: 0.0; color: "#E8EDE3" }
        GradientStop { position: 0.55; color: "#D6E1D0" }
        GradientStop { position: 1.0; color: "#B9CCB3" }
    }

    Image {
        readonly property int size: Math.min(root.width, root.height) * 0.36
        visible: !root.hasImage
        width: size
        height: size
        sourceSize: Qt.size(size, size)
        anchors { right: parent.right; bottom: parent.bottom; rightMargin: root.width * 0.08; bottomMargin: root.height * 0.1 }
        source: "file:///usr/share/icons/hicolor/scalable/apps/sedmio.svg"
        opacity: 0.13
    }

    // Картинка проявляется, когда загрузится, — без скачка с градиента.
    Item {
        anchors.fill: parent
        opacity: root.hasImage ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 300 } }

        Image {
            id: photo
            anchors.fill: parent
            source: root.image
            fillMode: Image.PreserveAspectCrop
            sourceSize: Qt.size(root.width, root.height)
            asynchronous: true
            cache: false
            visible: !root.dimmed
        }

        MultiEffect {
            anchors.fill: parent
            source: photo
            visible: root.dimmed
            blurEnabled: true
            blur: 0.7
            blurMax: 48
            autoPaddingEnabled: false
        }

        Rectangle {
            anchors.fill: parent
            visible: root.dimmed
            color: "#EEF1EA"
            opacity: 0.5
        }
    }
}
