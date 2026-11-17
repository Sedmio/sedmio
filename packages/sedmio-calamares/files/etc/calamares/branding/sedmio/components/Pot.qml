import QtQuick

// Терракотовый горшок с гравийной подсыпкой, вид сверху. Рисуется один раз.
// Свет тот же, что у растения: бортик отбрасывает тень внутрь, горшок —
// на бумагу.
Item {
    id: pot

    property real radius: 150       // внешний радиус бортика, px
    property real quality: 1.5
    property int seed: 7

    property bool ready: false      // нарисован

    // поля под тень: она уходит от света дальше всего
    readonly property real pad: Math.ceil(radius * 0.46)
    readonly property real gravelRadius: radius * 0.805

    width: 2 * (radius + pad)
    height: width

    readonly property var baked: [radius, quality, seed]
    onBakedChanged: Qt.callLater(canvas.requestPaint)

    Canvas {
        id: canvas

        width: Math.ceil(pot.width * pot.quality)
        height: width
        scale: 1 / pot.quality
        transformOrigin: Item.TopLeft
        antialiasing: true
        smooth: true
        renderStrategy: Canvas.Threaded
        onPainted: pot.ready = true

        function rgb(c) { return [c.r, c.g, c.b] }
        function mix(a, b, t) { return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t] }
        function col(c, a) { return Qt.rgba(c[0], c[1], c[2], a === undefined ? 1 : a) }

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            ctx.clearRect(0, 0, width, height)

            const q = pot.quality
            const R = pot.radius * q
            const c = width / 2
            const lx = Theme.lightX, ly = Theme.lightY

            // свой генератор случайных чисел: гравий всегда один и тот же
            let state = pot.seed * 2654435761 % 4294967296
            const rnd = () => {
                state = (state * 1664525 + 1013904223) % 4294967296
                return state / 4294967296
            }

            const clay = rgb(Theme.potClay), clayLight = rgb(Theme.potLight)
            const clayDark = rgb(Theme.potDark), clayDeep = rgb(Theme.potDeep)
            const sand = rgb(Theme.gravel), sandLight = rgb(Theme.gravelLight), sandDark = rgb(Theme.gravelDark)
            const dark = rgb(Theme.groundShadow)

            function disc(r, style) {
                ctx.fillStyle = style
                ctx.beginPath()
                ctx.arc(c, c, r, 0, 2 * Math.PI)
                ctx.fill()
            }
            // градиент вдоль света: from — со стороны света, to — с теневой
            function along(r, from, to) {
                const g = ctx.createLinearGradient(c + lx * r, c + ly * r, c - lx * r, c - ly * r)
                g.addColorStop(0, from)
                g.addColorStop(1, to)
                return g
            }
            function halo(cx, cy, r0, r1, stops) {
                const g = ctx.createRadialGradient(cx, cy, r0, cx, cy, r1)
                for (const s of stops)
                    g.addColorStop(s[0], s[1])
                ctx.fillStyle = g
                ctx.fillRect(cx - r1, cy - r1, 2 * r1, 2 * r1)
            }

            // ----- тень на бумаге: горшок высокий, тень длинная, мягкая и уходит от света
            const sh = R * 0.2
            halo(c - lx * sh, c - ly * sh, R * 0.6, R * 1.24, [
                [0, col(dark, 0.3)], [0.5, col(dark, 0.2)], [0.8, col(dark, 0.07)], [1, col(dark, 0)]])
            // и плотная у самого края
            halo(c - lx * R * 0.045, c - ly * R * 0.045, R * 0.95, R * 1.07, [
                [0, col(dark, 0.42)], [1, col(dark, 0)]])

            // ----- бортик: скруглённая внешняя кромка, плоский верх, кромка внутрь
            disc(R, along(R, col(mix(clayLight, [1, 1, 1], 0.2)), col(clayDeep)))
            disc(R * 0.978, along(R, col(clayLight), col(mix(clay, clayDark, 0.5))))
            disc(R * 0.955, along(R, col(mix(clayLight, clay, 0.25)), col(mix(clay, clayDark, 0.2))))
            disc(R * 0.885, along(R, col(mix(clay, clayDark, 0.6)), col(mix(clayLight, [1, 1, 1], 0.25))))

            // шероховатость обожжённой глины: крапинки и следы гончарного круга
            ctx.save()
            ctx.beginPath()
            ctx.arc(c, c, R, 0, 2 * Math.PI)
            ctx.clip()
            const specks = Math.round(pot.radius * 2.2)
            for (let i = 0; i < specks; ++i) {
                const ang = rnd() * 2 * Math.PI
                const rad = R * (0.87 + 0.13 * rnd())
                ctx.fillStyle = rnd() < 0.55 ? col(clayDeep, 0.1 + 0.16 * rnd()) : col([1, 1, 1], 0.1 + 0.2 * rnd())
                ctx.beginPath()
                ctx.arc(c + rad * Math.cos(ang), c + rad * Math.sin(ang), (0.35 + 0.75 * rnd()) * q, 0, 2 * Math.PI)
                ctx.fill()
            }
            ctx.lineWidth = Math.max(0.6, R * 0.004)
            for (const rr of [0.905, 0.928, 0.946]) {
                ctx.strokeStyle = col(clayDeep, 0.07)
                ctx.beginPath(); ctx.arc(c, c, R * rr, 0, 2 * Math.PI); ctx.stroke()
            }
            ctx.restore()

            // ----- внутренняя стенка: со стороны света она в тени, напротив — освещена
            disc(R * 0.865, along(R * 0.865, col(mix(clayDeep, dark, 0.25)), col(mix(clay, clayLight, 0.5))))

            // ----- гравий
            const Rg = pot.gravelRadius * q
            disc(Rg, along(Rg, col(mix(sand, sandDark, 0.25)), col(mix(sand, sandLight, 0.3))))

            ctx.save()
            ctx.beginPath()
            ctx.arc(c, c, Rg, 0, 2 * Math.PI)
            ctx.clip()

            // камешки: мелкие, вразнобой, у каждого своя тень
            const count = Math.round(pot.radius * pot.radius * 0.065)
            for (let i = 0; i < count; ++i) {
                const ang = rnd() * 2 * Math.PI
                const rad = Math.sqrt(rnd()) * Rg
                const x = c + rad * Math.cos(ang), y = c + rad * Math.sin(ang)
                const size = (0.9 + 2.3 * rnd() * rnd()) * q * Math.max(0.8, pot.radius / 150)
                const squash = 0.6 + 0.4 * rnd()
                const turn = rnd() * Math.PI
                const pick = rnd()
                let tint = pick < 0.5 ? mix(sand, sandLight, rnd()) : pick < 0.85 ? mix(sand, sandDark, rnd() * 0.8)
                         : pick < 0.93 ? mix(sand, clay, 0.35 + 0.3 * rnd()) : mix(sandDark, dark, 0.25 * rnd())
                for (const pass of [0, 1]) {       // сначала тень (в сторону от света), потом камешек
                    ctx.save()
                    ctx.translate(x - (pass ? 0 : lx * size * 0.4), y - (pass ? 0 : ly * size * 0.4))
                    ctx.rotate(turn)
                    ctx.scale(1, squash)
                    ctx.fillStyle = pass ? col(tint) : col(sandDark, 0.6)
                    ctx.beginPath()
                    ctx.arc(0, 0, size, 0, 2 * Math.PI)
                    ctx.fill()
                    ctx.restore()
                }
            }

            // тень бортика на гравии: серп со стороны света
            const d = R * 0.085
            halo(c - lx * d, c - ly * d, Rg * 0.84, Rg * 1.12, [
                [0, col(dark, 0)], [0.45, col(dark, 0.2)], [1, col(dark, 0.52)]])
            // лёгкое затемнение по всему краю: гравий ниже бортика
            halo(c, c, Rg * 0.86, Rg, [[0, col(dark, 0)], [1, col(dark, 0.2)]])
            ctx.restore()

            // гравий лежит ниже стенки: тонкая тень на стыке
            ctx.lineWidth = Math.max(1, R * 0.012)
            ctx.strokeStyle = col(dark, 0.3)
            ctx.beginPath(); ctx.arc(c, c, Rg, 0, 2 * Math.PI); ctx.stroke()
        }
    }
}
