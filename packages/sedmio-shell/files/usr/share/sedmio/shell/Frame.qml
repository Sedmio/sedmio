import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland

// Рамка вокруг экрана со скруглёнными внутренними углами, слева в неё
// встроена панель. Одно окно на весь экран поверх программ: рисовать
// можно где угодно (подсказки, позже — выезжающие панели), а мышь окно
// ловит только на рамке (mask), остальное уходит окнам под ним.
PanelWindow {
    id: frame
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "sedmio-frame"

    mask: Region {
        item: content
        Region { item: hole; intersection: Intersection.Subtract }
    }

    Item {
        id: content
        anchors.fill: parent

        // Проём рамки: здесь видны окна программ.
        Item {
            id: hole
            x: Theme.barWidth
            y: Theme.border
            width: frame.width - Theme.barWidth - Theme.border
            height: frame.height - 2 * Theme.border
        }

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            // Лёгкая тень с рамки на окна: рамка лежит поверх.
            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Theme.shadow
                shadowOpacity: 0.28
                shadowBlur: 0.7
                blurMax: 24
            }

            ShapePath {
                fillColor: Theme.paper
                strokeColor: "transparent"
                fillRule: ShapePath.OddEvenFill

                PathRectangle { x: 0; y: 0; width: frame.width; height: frame.height }
                PathRectangle {
                    x: hole.x; y: hole.y; width: hole.width; height: hole.height
                    radius: Theme.frameRadius
                }
            }
        }

        Bar {
            x: 0
            y: 0
            width: Theme.barWidth
            height: frame.height
            window: frame
            tooltip: tooltip
        }

        Tooltip { id: tooltip }
    }
}
