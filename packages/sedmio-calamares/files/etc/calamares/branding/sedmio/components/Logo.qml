import QtQuick

// Знак Sedmio: та же розетка седума, вид сверху, но нарисованная для
// маленького размера — три кольца крупных листьев по золотому углу,
// без мелких теней. Цвета и свет — как у большого растения.
Canvas {
    id: logo

    property int size: 28

    width: size
    height: size
    antialiasing: true

    onSizeChanged: requestPaint()

    onPaint: {
        const ctx = getContext("2d")
        ctx.reset()
        ctx.clearRect(0, 0, width, height)

        const s = logo.size, c = s / 2
        const lx = Theme.lightX, ly = Theme.lightY
        const rgb = v => [v.r, v.g, v.b]
        const mix = (a, b, t) => [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t]
        const col = (v, a) => Qt.rgba(v[0], v[1], v[2], a === undefined ? 1 : a)

        // лист: основание в начале координат, кончик вверх; grow — припуск наружу
        function leafPath(len, wid, grow) {
            const hw = wid / 2 + grow, top = -len - grow
            ctx.beginPath()
            ctx.moveTo(0, grow)
            ctx.bezierCurveTo(hw * 0.7, -len * 0.05, hw, -len * 0.34, hw, -len * 0.56)
            ctx.bezierCurveTo(hw, -len * 0.8, hw * 0.36, top * 0.93, 0, top)
            ctx.bezierCurveTo(-hw * 0.36, top * 0.93, -hw, -len * 0.8, -hw, -len * 0.56)
            ctx.bezierCurveTo(-hw, -len * 0.34, -hw * 0.7, -len * 0.05, 0, grow)
            ctx.closePath()
        }

        // кольца: [сколько листьев, длина, ширина, цвет основания, цвет середины, цвет кончика]
        const blush = rgb(Theme.plantBlush), dark = rgb(Theme.plantShadow)
        const rings = [
            [5, 0.5, 0.34, rgb(Theme.plantDeep), rgb(Theme.plantMid), mix(rgb(Theme.plantLight), blush, 0.85)],
            [5, 0.37, 0.27, rgb(Theme.plantMid), rgb(Theme.plantLight), rgb(Theme.plantPale)],
            [3, 0.21, 0.17, rgb(Theme.plantYoung), rgb(Theme.plantYoungLight), rgb(Theme.plantYoungPale)]
        ]
        const gap = Math.max(0.5, s * 0.024)
        let index = 0
        for (const ring of rings) {
            for (let i = 0; i < ring[0]; ++i, ++index) {
                const turn = index * 137.508 * Math.PI / 180
                const len = ring[1] * s, wid = ring[2] * s
                // свет в осях листа
                const ux = lx * Math.cos(turn) + ly * Math.sin(turn)
                const uy = -lx * Math.sin(turn) + ly * Math.cos(turn)

                ctx.save()
                ctx.translate(c, c)
                ctx.rotate(turn)
                // тень на листья ниже: тот же контур, чуть шире и сдвинут от света
                ctx.save()
                ctx.translate(-ux * gap * 0.7, -uy * gap * 0.7)
                leafPath(len, wid, gap * 0.55)
                ctx.fillStyle = col(dark, 0.5)
                ctx.fill()
                ctx.restore()

                // лист: от основания к кончику, у внешних кончик румяный
                const g = ctx.createLinearGradient(0, 0, 0, -len)
                g.addColorStop(0.2, col(ring[3]))
                g.addColorStop(0.62, col(ring[4]))
                g.addColorStop(0.82, col(mix(ring[4], ring[5], 0.45)))
                g.addColorStop(1, col(ring[5]))
                leafPath(len, wid, 0)
                ctx.fillStyle = g
                ctx.fill()

                // объём: сторона к свету светлее, от света — темнее
                const gs = ctx.createLinearGradient(-wid / 2, 0, wid / 2, 0)
                gs.addColorStop(ux > 0 ? 0 : 1, col(dark, 0.34 * Math.abs(ux)))
                gs.addColorStop(0.5, col(dark, 0))
                gs.addColorStop(ux > 0 ? 1 : 0, col([1, 1, 1], 0.2 * Math.abs(ux)))
                ctx.fillStyle = gs
                ctx.fill()
                ctx.restore()
            }
        }
    }
}
