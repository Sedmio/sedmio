import QtQuick
import QtQuick.Shapes

// Фон за растением: крупные мягкие пятна шалфея и терракоты, медленно
// дрейфуют и еле угадываются.
//
// Пятна — радиальные градиенты, которые сами сходят на нет к краю.
// Размытие (MultiEffect) здесь не годится: его обрезает граница слоя,
// и в Calamares на пятнах были видны резкие прямые края.
Item {
    id: root

    component Blob: Shape {
        id: blob

        property color tint
        property real strength: 0.7
        readonly property real r: width / 2

        height: width
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: -1
            fillGradient: RadialGradient {
                centerX: blob.r; centerY: blob.r
                centerRadius: blob.r
                focalX: blob.r; focalY: blob.r
                GradientStop { position: 0.0; color: Qt.rgba(blob.tint.r, blob.tint.g, blob.tint.b, blob.strength) }
                GradientStop { position: 0.45; color: Qt.rgba(blob.tint.r, blob.tint.g, blob.tint.b, blob.strength * 0.55) }
                GradientStop { position: 0.75; color: Qt.rgba(blob.tint.r, blob.tint.g, blob.tint.b, blob.strength * 0.18) }
                GradientStop { position: 1.0; color: Qt.rgba(blob.tint.r, blob.tint.g, blob.tint.b, 0) }
            }
            PathAngleArc {
                centerX: blob.r; centerY: blob.r
                radiusX: blob.r; radiusY: blob.r
                startAngle: 0; sweepAngle: 360
            }
        }
    }

    Blob {
        tint: Theme.leafPale
        strength: 0.75
        width: Math.min(root.width, root.height) * 1.05
        x: root.width * 0.5 - width * 0.55
        y: root.height * 0.42 - width / 2
        SequentialAnimation on x {
            loops: Animation.Infinite
            NumberAnimation { to: root.width * 0.5 - root.width * 0.62; duration: 14000; easing.type: Easing.InOutSine }
            NumberAnimation { to: root.width * 0.5 - root.width * 0.5; duration: 14000; easing.type: Easing.InOutSine }
        }
    }

    Blob {
        tint: Theme.terracottaSoft
        strength: 0.8
        width: Math.min(root.width, root.height) * 0.75
        x: root.width * 0.62 - width / 2
        y: root.height * 0.62 - width / 2
        SequentialAnimation on y {
            loops: Animation.Infinite
            NumberAnimation { to: root.height * 0.5 - root.height * 0.38; duration: 11000; easing.type: Easing.InOutSine }
            NumberAnimation { to: root.height * 0.62 - root.height * 0.38; duration: 11000; easing.type: Easing.InOutSine }
        }
    }
}
