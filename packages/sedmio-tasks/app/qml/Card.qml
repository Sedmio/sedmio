// Копия из sedmio-preferences (app/qml): диспетчер задач — отдельный пакет,
// чтобы сломанное обновление «Параметров» не задело инструмент спасения.
// Меняя оформление, менять в обоих местах.
import QtQuick

// Карточка с параметрами: строки (Setting) друг под другом, между ними линия.
Rectangle {
    id: root
    property string title
    default property alias content: column.data

    width: parent ? parent.width : 0
    implicitHeight: (title !== "" ? heading.height + 8 : 0) + frame.height
    color: "transparent"

    SText {
        id: heading
        visible: root.title !== ""
        text: root.title
        size: 13
        weight: 600
        color: Theme.inkSoft
        leftPadding: 4
    }

    Rectangle {
        id: frame
        y: root.title !== "" ? heading.height + 8 : 0
        width: parent.width
        height: column.height
        radius: Theme.radius
        color: Theme.surface
        border.width: 1
        border.color: Theme.line

        Column {
            id: column
            width: parent.width
        }
    }
}
