pragma Singleton
import QtQuick
import Quickshell

// «Пружинное» движение: то, что выезжает или встаёт на место, чуть
// проскакивает и возвращается (кривые Material 3 Expressive, spatial).
// Для ящиков рамки, дока, меню и перетаскиваемых кнопок. Цвет,
// прозрачность и закрытие — без перелёта: Theme.animFast/animNormal.
//   NumberAnimation { duration: Motion.springDuration
//                     easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.spring }
Singleton {
    // Мягкая — большое: ящики рамки, док, кнопки на место.
    readonly property var spring: [0.38, 1.21, 0.22, 1.0, 1, 1]
    readonly property int springDuration: 420
    // Быстрая — маленькое: меню, миниатюры окон.
    readonly property var springFast: [0.42, 1.67, 0.21, 0.90, 1, 1]
    readonly property int springFastDuration: 320
}
