import QtQuick
import QtQuick.Shapes
import Sedmio.Style

// Выезжающая панель, приросшая к нижней полосе рамки (индикаторы громкости,
// яркости, раскладки). По бокам у стыка с рамкой вогнутые скругления,
// сверху выпуклые углы. Рисуется в общем слое рамки — тень общая.
//
//      ╭───────────╮
//      │           │
//   ───╯           ╰───   ← нижняя полоса рамки
Shape {
    id: root
    property real centerX            // середина панели по горизонтали
    property real edgeY              // верхний край нижней полосы рамки
    property real drawerWidth
    property real drawerHeight
    property real radius: Theme.frameRadius
    property real fillet: Theme.frameRadius
    property color color: Theme.paper

    readonly property real x0: centerX - drawerWidth / 2
    readonly property real topY: edgeY - drawerHeight
    readonly property real r: Math.min(radius, drawerHeight / 2, drawerWidth / 2)
    readonly property real f: Math.min(fillet, drawerHeight)

    anchors.fill: parent
    visible: drawerHeight > 0.5
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
        fillColor: root.color
        strokeColor: "transparent"
        startX: root.x0 - root.f
        startY: root.edgeY

        // Левый вогнутый стык с рамкой
        PathArc {
            x: root.x0; y: root.edgeY - root.f
            radiusX: root.f; radiusY: root.f
            direction: PathArc.Counterclockwise
        }
        PathLine { x: root.x0; y: root.topY + root.r }
        PathArc {
            x: root.x0 + root.r; y: root.topY
            radiusX: root.r; radiusY: root.r
        }
        PathLine { x: root.x0 + root.drawerWidth - root.r; y: root.topY }
        PathArc {
            x: root.x0 + root.drawerWidth; y: root.topY + root.r
            radiusX: root.r; radiusY: root.r
        }
        PathLine { x: root.x0 + root.drawerWidth; y: root.edgeY - root.f }
        // Правый вогнутый стык с рамкой
        PathArc {
            x: root.x0 + root.drawerWidth + root.f; y: root.edgeY
            radiusX: root.f; radiusY: root.f
            direction: PathArc.Counterclockwise
        }
        PathLine { x: root.x0 - root.f; y: root.edgeY }
    }
}
