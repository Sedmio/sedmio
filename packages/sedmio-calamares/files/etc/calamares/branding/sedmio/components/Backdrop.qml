import QtQuick
import QtQuick.Effects

// Фон за растением: крупные мягкие пятна шалфея и терракоты,
// сильно размытые и медленно дрейфующие. Должны еле угадываться.
Item {
    id: root

    clip: true

    Item {
        id: blobs
        anchors.fill: parent
        visible: false

        Rectangle {
            id: sage
            width: root.width * 0.8
            height: width
            radius: width / 2
            color: Theme.leafPale
            x: root.width * 0.15
            y: root.height * 0.1
            SequentialAnimation on x {
                loops: Animation.Infinite
                NumberAnimation { to: root.width * 0.05; duration: 14000; easing.type: Easing.InOutSine }
                NumberAnimation { to: root.width * 0.18; duration: 14000; easing.type: Easing.InOutSine }
            }
        }

        Rectangle {
            width: root.width * 0.5
            height: width
            radius: width / 2
            color: Theme.terracottaSoft
            x: root.width * 0.45
            y: root.height * 0.45
            SequentialAnimation on y {
                loops: Animation.Infinite
                NumberAnimation { to: root.height * 0.32; duration: 11000; easing.type: Easing.InOutSine }
                NumberAnimation { to: root.height * 0.5; duration: 11000; easing.type: Easing.InOutSine }
            }
        }
    }

    MultiEffect {
        anchors.fill: parent
        source: blobs
        blurEnabled: true
        blur: 1.0
        blurMax: 64
        opacity: 0.75
    }
}
