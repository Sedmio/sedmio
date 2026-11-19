import QtQuick
import QtQuick.Effects

// Круглая картинка пользователя; нет картинки — первая буква имени.
Item {
    id: root
    property url source
    property string name
    implicitWidth: 96
    implicitHeight: 96

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: Theme.greenWash
        border.width: 1
        border.color: Theme.line
        // Круг и под картинкой: у прозрачных картинок (Konqi и т. п.) иначе
        // нет границы.

        SText {
            anchors.centerIn: parent
            visible: picture.status !== Image.Ready
            text: root.name.charAt(0).toUpperCase()
            size: root.width * 0.42
            weight: 550
            color: Theme.green
        }
    }

    Image {
        id: picture
        anchors.fill: parent
        source: root.source
        sourceSize: Qt.size(width * 2, height * 2)
        fillMode: Image.PreserveAspectCrop
        visible: false
    }
    Rectangle {
        id: mask
        anchors.fill: parent
        radius: width / 2
        visible: false
        layer.enabled: true
    }
    MultiEffect {
        anchors.fill: parent
        source: picture
        maskEnabled: true
        maskSource: mask
        visible: picture.status === Image.Ready
    }
}
