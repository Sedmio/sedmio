import QtQuick
import QtQuick.Shapes
import Sedmio.Style

// Выезжающая панель, приросшая к рамке: левым краем — к панели слева,
// верхним — к верхней полосе рамки. На стыках вогнутые скругления, чтобы
// рамка и панель читались одной поверхностью; внешний угол — выпуклый.
// Рисуется внутри общего слоя рамки, поэтому тень у них общая.
//
//   ┌──────────────╮   ← вогнутое скругление у верхней полосы
//   │              │
//   │              │
//   ╰──────────────╯   ← выпуклый угол
//   ↑ вогнутое скругление у панели слева
Shape {
    id: root
    property real x0
    property real y0
    property real drawerWidth
    property real drawerHeight
    property real radius: Theme.frameRadius
    property real fillet: Theme.frameRadius
    property color color: Theme.paper

    // На маленькой высоте (начало анимации) скругления не больше половины.
    readonly property real r: Math.min(radius, drawerHeight / 2)
    readonly property real f: Math.min(fillet, drawerHeight / 2)

    anchors.fill: parent
    visible: drawerHeight > 0.5
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
        fillColor: root.color
        strokeColor: "transparent"
        startX: root.x0
        startY: root.y0

        // Верхний край вдоль полосы рамки и вогнутый стык с ней
        PathLine { x: root.x0 + root.drawerWidth + root.f; y: root.y0 }
        PathArc {
            x: root.x0 + root.drawerWidth; y: root.y0 + root.f
            radiusX: root.f; radiusY: root.f
            direction: PathArc.Counterclockwise
        }
        // Правый край и выпуклый нижний угол
        PathLine { x: root.x0 + root.drawerWidth; y: root.y0 + root.drawerHeight - root.r }
        PathArc {
            x: root.x0 + root.drawerWidth - root.r; y: root.y0 + root.drawerHeight
            radiusX: root.r; radiusY: root.r
            direction: PathArc.Clockwise
        }
        // Нижний край и вогнутый стык с панелью слева
        PathLine { x: root.x0 + root.f; y: root.y0 + root.drawerHeight }
        PathArc {
            x: root.x0; y: root.y0 + root.drawerHeight + root.f
            radiusX: root.f; radiusY: root.f
            direction: PathArc.Counterclockwise
        }
        PathLine { x: root.x0; y: root.y0 }
    }
}
