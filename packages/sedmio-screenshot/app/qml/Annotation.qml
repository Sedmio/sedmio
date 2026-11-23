import QtQuick
import QtQuick.Shapes
import Sedmio.Style

// Одна пометка на снимке, в точках снимка (родитель — во весь снимок).
// Пометка — простой объект (EditorWindow.qml):
//   pen, marker     {type, color, width, points: [{x, y}…]}
//   arrow, rect,
//   ellipse, hide   {type, color, width, x1, y1, x2, y2}
//   text            {type, color, size, x, y, text, w, h}
// hide — область крупными квадратами (пиксели снимка под ней не видны).
Item {
    id: root
    property var a: ({ type: "" })
    // Снимок без пометок — для hide.
    property Item base

    readonly property string type: a ? a.type : ""
    readonly property bool shape: ["pen", "marker", "arrow", "rect", "ellipse"].includes(type)
    readonly property real boxLeft: Math.min(a.x1 ?? 0, a.x2 ?? 0)
    readonly property real boxTop: Math.min(a.y1 ?? 0, a.y2 ?? 0)
    readonly property real boxWidth: Math.abs((a.x2 ?? 0) - (a.x1 ?? 0))
    readonly property real boxHeight: Math.abs((a.y2 ?? 0) - (a.y1 ?? 0))

    function f(v) { return Number(v).toFixed(1); }

    // Линия пометки — путь SVG.
    readonly property string line: {
        switch (type) {
        case "pen":
        case "marker": {
            const p = a.points || [];
            if (p.length === 0) return "";
            let s = "M " + f(p[0].x) + " " + f(p[0].y);
            // Точка — короткий штрих: круглые концы рисуют кружок.
            if (p.length === 1) return s + " L " + f(p[0].x + 0.05) + " " + f(p[0].y);
            for (let i = 1; i < p.length; i++) s += " L " + f(p[i].x) + " " + f(p[i].y);
            return s;
        }
        case "arrow": {
            const g = arrowGeometry;
            return "M " + f(a.x1) + " " + f(a.y1) + " L " + f(g.bx) + " " + f(g.by);
        }
        case "rect": {
            const r = Math.min(6, boxWidth / 2, boxHeight / 2);
            const x = boxLeft, y = boxTop, w = boxWidth, h = boxHeight;
            return "M " + f(x + r) + " " + f(y) + " L " + f(x + w - r) + " " + f(y)
                + " Q " + f(x + w) + " " + f(y) + " " + f(x + w) + " " + f(y + r)
                + " L " + f(x + w) + " " + f(y + h - r)
                + " Q " + f(x + w) + " " + f(y + h) + " " + f(x + w - r) + " " + f(y + h)
                + " L " + f(x + r) + " " + f(y + h)
                + " Q " + f(x) + " " + f(y + h) + " " + f(x) + " " + f(y + h - r)
                + " L " + f(x) + " " + f(y + r)
                + " Q " + f(x) + " " + f(y) + " " + f(x + r) + " " + f(y) + " Z";
        }
        case "ellipse": {
            const rx = Math.max(0.5, boxWidth / 2), ry = Math.max(0.5, boxHeight / 2);
            const cx = boxLeft + rx, cy = boxTop + ry;
            return "M " + f(cx - rx) + " " + f(cy)
                + " A " + f(rx) + " " + f(ry) + " 0 1 0 " + f(cx + rx) + " " + f(cy)
                + " A " + f(rx) + " " + f(ry) + " 0 1 0 " + f(cx - rx) + " " + f(cy) + " Z";
        }
        }
        return "";
    }

    // Стрелка: острие в (x2, y2), линия кончается у основания острия.
    readonly property var arrowGeometry: {
        if (type !== "arrow") return ({ bx: 0, by: 0, head: "" });
        const dx = a.x2 - a.x1, dy = a.y2 - a.y1;
        const len = Math.max(0.001, Math.hypot(dx, dy));
        const ux = dx / len, uy = dy / len;
        const head = Math.min(len, Math.max(16, a.width * 5.5));
        const half = head * 0.5;
        const baseX = a.x2 - ux * head, baseY = a.y2 - uy * head;
        return {
            bx: a.x2 - ux * head * 0.7,
            by: a.y2 - uy * head * 0.7,
            head: "M " + f(a.x2) + " " + f(a.y2)
                + " L " + f(baseX - uy * half) + " " + f(baseY + ux * half)
                + " L " + f(baseX + uy * half) + " " + f(baseY - ux * half) + " Z"
        };
    }

    Shape {
        anchors.fill: parent
        visible: root.shape
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: root.type === "marker" ? Qt.alpha(root.a.color, 0.45) : (root.a.color ?? "transparent")
            strokeWidth: root.a.width ?? 1
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: root.line }
        }
        ShapePath {
            strokeColor: root.a.color ?? "transparent"
            strokeWidth: root.type === "arrow" ? Math.max(1, (root.a.width ?? 1) * 0.6) : 0
            fillColor: root.type === "arrow" ? root.a.color : "transparent"
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: root.arrowGeometry.head }
        }
    }

    Text {
        visible: root.type === "text"
        x: root.a.x ?? 0
        y: root.a.y ?? 0
        text: root.a.text ?? ""
        color: root.a.color ?? Theme.ink
        font.family: Theme.fontFamily
        font.pixelSize: root.a.size ?? 24
        font.variableAxes: ({ "wght": 600 })
    }

    // Крупные квадраты: снимок под областью, сжатый и растянутый без
    // сглаживания.
    ShaderEffectSource {
        visible: root.type === "hide" && root.base !== null && width >= 1 && height >= 1
        x: root.boxLeft
        y: root.boxTop
        width: root.boxWidth
        height: root.boxHeight
        sourceItem: visible ? root.base : null
        sourceRect: Qt.rect(root.boxLeft, root.boxTop, root.boxWidth, root.boxHeight)
        readonly property real block: Math.max(10, Math.min(root.boxWidth, root.boxHeight) / 10)
        textureSize: Qt.size(Math.max(1, Math.ceil(root.boxWidth / block)), Math.max(1, Math.ceil(root.boxHeight / block)))
        smooth: false
    }
}
