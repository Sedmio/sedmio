import QtQuick

// Растворение у края прокручиваемого списка: строки не обрезаются ножом,
// а уходят в фон. Ставится поверх списка, цвет — цвет подложки под ним.
Rectangle {
    id: fade

    property Flickable view
    property bool atTop: false
    property color tint: Theme.paper
    readonly property color clear: Qt.rgba(tint.r, tint.g, tint.b, 0)

    anchors.left: view.left
    anchors.right: view.right
    y: atTop ? view.y : view.y + view.height - height
    height: 36
    opacity: (atTop ? !view.atYBeginning : !view.atYEnd) ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Theme.animNormal } }

    gradient: Gradient {
        GradientStop { position: 0; color: fade.atTop ? fade.tint : fade.clear }
        GradientStop { position: 1; color: fade.atTop ? fade.clear : fade.tint }
    }
}
