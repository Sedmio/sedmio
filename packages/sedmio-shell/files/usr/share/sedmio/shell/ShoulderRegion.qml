import QtQuick
import Quickshell

// Размытие под вогнутым «плечом» выезжающего ящика (DrawerShape,
// EdgeDrawerShape): квадрат f×f без четверти круга радиуса f с центром
// (cx, cy). Без него плечо над светлым окном — белый уголок рядом с
// размытым ящиком. f = 0 — пусто (ящик спрятан).
Region {
    id: root
    property real f: 0
    property real sx: 0     // левый верхний угол квадрата
    property real sy: 0
    property real cx: 0     // центр выреза
    property real cy: 0

    intersection: Intersection.Combine
    x: Math.round(sx)
    y: Math.round(sy)
    width: f > 0.5 ? Math.round(f) : 0
    height: f > 0.5 ? Math.round(f) : 0

    Region {
        shape: RegionShape.Ellipse
        intersection: Intersection.Subtract
        x: Math.round(root.cx - root.f)
        y: Math.round(root.cy - root.f)
        width: Math.round(2 * root.f)
        height: Math.round(2 * root.f)
    }
}
