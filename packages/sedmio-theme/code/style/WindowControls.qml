import QtQuick
import QtQuick.Shapes

// Кнопки окна — свернуть, развернуть, закрыть — для программ, что сами
// рисуют заголовок (Theme.clientTitleBar, common/ownheader.h). Рамка не
// наша — у неё свои кнопки, здесь пусто. С виду как кнопки рамки
// (decoration/button.cpp): кружок при наведении, закрыть — терракотовый.
Row {
    id: root
    readonly property Window win: Window.window
    property bool minimizable: true
    property bool maximizable: true
    readonly property bool maximized: !!win && win.visibility === Window.Maximized
    readonly property bool active: !!win && win.active

    visible: Theme.clientTitleBar
    spacing: 2

    component WindowButton: Item {
        id: button
        property string glyph
        property bool danger: false
        signal activated()

        width: 28
        height: 28
        readonly property bool hot: area.containsMouse || area.pressed

        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: width / 2
            color: area.pressed ? (button.danger ? Qt.darker(Theme.terracotta, 1.15) : Theme.greenSelect)
                 : area.containsMouse ? (button.danger ? Theme.terracotta : Theme.greenWash)
                 : Qt.alpha(Theme.greenWash, 0)
            Behavior on color { ColorAnimation { duration: Theme.animFast } }
        }
        Shape {
            anchors.centerIn: parent
            width: 28
            height: 28
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeWidth: 1.5
                strokeColor: button.danger && button.hot ? Theme.textOnGreen
                           : root.active ? Theme.inkSoft : Theme.inkMuted
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathSvg { path: button.glyph }
            }
        }
        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            onClicked: button.activated()
        }
    }

    WindowButton {
        visible: root.minimizable
        glyph: "M 9.5 14.5 L 18.5 14.5"
        onActivated: root.win.showMinimized()
    }
    WindowButton {
        visible: root.maximizable
        // Развёрнуто — два окна (вернуть прежний размер), иначе квадрат.
        glyph: root.maximized
            ? "M 11 12 L 14.5 12 Q 16 12 16 13.5 L 16 17 Q 16 18.5 14.5 18.5 L 11 18.5 Q 9.5 18.5 9.5 17 L 9.5 13.5 Q 9.5 12 11 12 Z "
              + "M 12 10.5 L 12 9.5 L 18.5 9.5 L 18.5 16 L 17.5 16"
            : "M 11.5 9.5 L 16.5 9.5 Q 18.5 9.5 18.5 11.5 L 18.5 16.5 Q 18.5 18.5 16.5 18.5 L 11.5 18.5 Q 9.5 18.5 9.5 16.5 L 9.5 11.5 Q 9.5 9.5 11.5 9.5 Z"
        onActivated: root.maximized ? root.win.showNormal() : root.win.showMaximized()
    }
    WindowButton {
        danger: true
        glyph: "M 10 10 L 18 18 M 18 10 L 10 18"
        onActivated: root.win.close()
    }
}
