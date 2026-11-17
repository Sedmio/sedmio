import QtQuick

// Лист суккулента, вид сверху. Рисуется один раз в текстуру (Canvas),
// как иллюстрация кистью: мягкая тень на листья ниже, объём, свет
// по краю, тень в глубине розетки, румянец на кончике. Дальше лист только
// двигают, вращают и масштабируют — это дёшево.
//
// Лист «запекают» под конкретный возраст: молодой — короткий, широкий
// у основания, свежего зелёного цвета; взрослый — ложечкой с острым
// кончиком, сизо-зелёный; старый — с румянцем по кончику и краю.
//
// Размытия в Canvas слишком медленные, поэтому мягкость набирается
// градиентами и стопкой полупрозрачных контуров: каждый чуть меньше
// (или чуть дальше) предыдущего. Рисование идёт в отдельном потоке
// и интерфейс не держит.
Item {
    id: leaf

    // ---------- что рисуем
    property real length: 100       // длина на экране, px
    property real breadth: 50       // ширина, px
    property real youth: 0          // 1 — только что появился, 0 — взрослый
    property real blush: 0          // 0..1 — румянец
    property real azimuth: 0        // куда смотрит кончик на экране, градусы (0 — вверх)
    property real cover: 0.5        // какая доля длины спрятана под листьями выше
    property real lift: 1           // насколько лист приподнят над нижними: длина тени
    property real hang: 1           // с какой доли длины лист висит над пустотой (тень там слабеет); 1 — нигде
    property real seed: 0           // характер листа
    property real quality: 1.5      // запас разрешения текстуры

    // Нарисован ли лист. Розетка ждёт все листья и показывает их разом (см. Sedum)
    property bool ready: false

    // Точка основания листа в координатах элемента: вокруг неё его вращают
    readonly property real pad: Math.ceil(length * 0.14 + 3)
    readonly property real baseX: width / 2
    readonly property real baseY: height - pad

    width: Math.ceil(breadth + 2 * pad)
    height: Math.ceil(length + 2 * pad)

    // Перерисовка — когда меняется что-то из запекаемого, не чаще раза за кадр
    readonly property var baked: [length, breadth, youth, blush, azimuth, cover, lift, hang, seed, quality]
    onBakedChanged: Qt.callLater(canvas.requestPaint)

    Canvas {
        id: canvas

        width: Math.ceil(leaf.width * leaf.quality)
        height: Math.ceil(leaf.height * leaf.quality)
        scale: 1 / leaf.quality
        transformOrigin: Item.TopLeft
        antialiasing: true
        smooth: true
        renderStrategy: Canvas.Threaded

        onPainted: if (leaf.length >= 1) leaf.ready = true

        // Детерминированный «шум»
        function noise(salt) {
            const v = Math.sin(leaf.seed * 12.9898 + salt * 78.233) * 43758.5453
            return v - Math.floor(v)
        }
        function mix(a, b, t) { return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t] }
        function rgb(c) { return [c.r, c.g, c.b] }
        function col(c, a) { return Qt.rgba(c[0], c[1], c[2], a === undefined ? 1 : a) }

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            ctx.clearRect(0, 0, width, height)
            if (leaf.length < 1)
                return

            const q = leaf.quality
            const L = leaf.length * q, W = leaf.breadth * q
            const hw = W / 2
            const cx = leaf.baseX * q, by = leaf.baseY * q
            const y = leaf.youth, bl = leaf.blush

            // ----- свет в осях листа (x вправо, y вниз, кончик вверх)
            const a = leaf.azimuth * Math.PI / 180
            const lx = Theme.lightX * Math.cos(a) + Theme.lightY * Math.sin(a)
            const ly = -Theme.lightX * Math.sin(a) + Theme.lightY * Math.cos(a)

            // ----- форма: молодой лист — широкий у основания и острый,
            // взрослый — ложечка с коротким остриём
            const tm = 0.64 - 0.22 * y                  // где лист шире всего
            const b = 0.38 + 0.40 * y                   // ширина основания
            const aR = 1 + 0.06 * (noise(1) - 0.5), aL = 2 - aR
            const bend = (noise(2) - 0.5) * 0.05 * (1 - y)

            // Преобразование контура: масштаб k вокруг точки (px, py)
            // и сдвиг, нарастающий от основания к кончику (тень)
            let k = 1, px = 0, py = 0, sx = 0, sy = 0
            const PX = (u, t) => {
                const x = cx + u * hw * (u > 0 ? aR : aL) + bend * L * t * t
                return px + (x - px) * k + sx * t
            }
            const PY = t => py + (by - t * L - py) * k + sy * t
            function outline() {
                const k1 = tm * 0.42, k2 = tm * 0.62
                const k3 = tm + (1 - tm) * 0.56, k4 = 0.94 - 0.025 * y, u4 = 0.37 - 0.1 * y
                const u1 = b + (1 - b) * 0.35
                ctx.moveTo(PX(b, 0), PY(0))
                ctx.bezierCurveTo(PX(u1, k1), PY(k1), PX(1, k2), PY(k2), PX(1, tm), PY(tm))
                ctx.bezierCurveTo(PX(1, k3), PY(k3), PX(u4, k4), PY(k4), PX(0, 1), PY(1))
                ctx.bezierCurveTo(PX(-u4, k4), PY(k4), PX(-1, k3), PY(k3), PX(-1, tm), PY(tm))
                ctx.bezierCurveTo(PX(-1, k2), PY(k2), PX(-u1, k1), PY(k1), PX(-b, 0), PY(0))
                ctx.closePath()
            }
            function reset() { k = 1; px = 0; py = 0; sx = 0; sy = 0 }
            function fillLeaf(style) {
                ctx.fillStyle = style
                ctx.beginPath(); outline(); ctx.fill()
            }
            // Полоса вдоль края: всё внутри листа, что снаружи контура,
            // сжатого к точке (cxp, cyp). Стопка таких полос — мягкий переход.
            // total — плотность у самого края, kMin — как глубоко заходит.
            function band(style, total, n, kMin, cxp, cyp, power) {
                ctx.fillRule = Qt.OddEvenFill
                ctx.fillStyle = style
                px = cxp; py = cyp
                for (let i = 0; i < n; ++i) {
                    k = 1 - (1 - kMin) * Math.pow((i + 1) / n, power)
                    ctx.globalAlpha = total * 2 * (n - i) / (n * (n + 1))
                    ctx.beginPath()
                    ctx.rect(0, 0, canvas.width, canvas.height)
                    outline()
                    ctx.fill()
                }
                ctx.globalAlpha = 1
                ctx.fillRule = Qt.WindingFill
                reset()
            }

            // Пластинка листа близка к эллипсу с центром в самом широком месте
            const ecx = cx + bend * L * tm * tm, ecy = by - tm * L
            const ex = hw, ey = (1 - tm) * L
            function rimPoint(dx, dy) {     // точка края эллипса в сторону (dx, dy)
                const t = 1 / Math.sqrt(dx * dx / (ex * ex) + dy * dy / (ey * ey))
                return [ecx + dx * t, ecy + dy * t]
            }
            const lit = rimPoint(lx, ly), dark = rimPoint(-lx, -ly)

            // ----- цвета: у каждого листа чуть свой тон, часть — холоднее
            const tone = 1 + 0.07 * (noise(3) - 0.5)
            const cool = 0.5 * noise(4) * (1 - y)
            const pick = (young, grown) => {
                const m = mix(rgb(grown), rgb(young), y)
                return [Math.min(1, m[0] * tone * (1 - 0.1 * cool)), Math.min(1, m[1] * tone),
                        Math.min(1, m[2] * tone * (1 + 0.1 * cool))]
            }
            const cShade = pick(Theme.plantYoungShade, Theme.plantShade)
            const cDeep = pick(Theme.plantYoungDeep, Theme.plantDeep)
            const cMid = pick(Theme.plantYoung, Theme.plantMid)
            const cLight = pick(Theme.plantYoungLight, Theme.plantLight)
            const cPale = pick(Theme.plantYoungPale, Theme.plantPale)
            const cGlow = rgb(Theme.plantGlow)
            const cDark = rgb(Theme.plantShadow)
            const cCast = rgb(Theme.groundShadow)
            const cBlush = rgb(Theme.plantBlush)
            const cBlushSoft = rgb(Theme.plantBlushSoft)

            // ----- 1. тень на то, что ниже: контур «съезжает» от света, тем дальше,
            // чем ближе к кончику — кончик приподнят над нижними листьями.
            // Шаг — около пикселя текстуры, поэтому ступенек не видно.
            const lift = leaf.lift
            if (lift > 0) {
                const far = L * 0.11 * lift
                const n = Math.max(4, Math.min(40, Math.ceil(far / 1.1)))
                // где лист свисает за край горшка, до бумаги далеко: тень там почти теряется
                const hang = Math.max(0, Math.min(1, leaf.hang))
                const gc = ctx.createLinearGradient(0, by, 0, by - L)
                gc.addColorStop(0, col(cCast, 0.6))
                gc.addColorStop(Math.max(0.01, hang - 0.08), col(cCast, 0.6))
                gc.addColorStop(Math.min(1, hang + 0.06), col(cCast, hang < 1 ? 0.2 : 0.6))
                gc.addColorStop(1, col(cCast, hang < 1 ? 0.2 : 0.6))
                px = ecx; py = ecy
                for (let i = n; i >= 1; --i) {
                    const f = i / n
                    sx = -lx * far * f; sy = -ly * far * f
                    k = 1 + 0.02 * f
                    ctx.globalAlpha = 2 * (n + 1 - i) / (n * (n + 1))
                    fillLeaf(gc)
                }
                ctx.globalAlpha = 1
                reset()
            }

            // ----- 2. тело: от тени в глубине розетки к светлому кончику
            const c = Math.max(0, Math.min(0.9, leaf.cover))
            const v = f => c + (1 - c) * f      // доля видимой части → доля длины
            const g = ctx.createLinearGradient(0, by, 0, by - L)
            g.addColorStop(0, col(cShade))
            g.addColorStop(Math.max(0.01, c * 0.7), col(cShade))
            g.addColorStop(v(0.02), col(cDeep))
            g.addColorStop(v(0.3), col(cMid))
            g.addColorStop(v(0.68), col(cLight))
            g.addColorStop(1, col(cPale))
            fillLeaf(g)

            // ----- 3. всё дальше — только внутри контура
            ctx.save()
            ctx.beginPath(); outline(); ctx.clip()

            // румянец: от края внутрь, гуще к кончику. Между зелёным и красным —
            // тёплый светлый переход, как у настоящего листа на солнце
            if (bl > 0.01) {
                const along = (color, from, power) => {
                    const gm = ctx.createLinearGradient(0, PY(from), 0, PY(1))
                    gm.addColorStop(0, col(color, 0))
                    gm.addColorStop(0.5, col(color, 0.35 * power))
                    gm.addColorStop(1, col(color, power))
                    return gm
                }
                band(along(rgb(Theme.plantBlushWarm), tm * 0.75, Math.sqrt(bl)), 0.8, 10, 0.5, ecx, ecy, 1.1)
                band(along(cBlushSoft, tm * 0.9, bl), 0.8, 7, 0.76, ecx, ecy, 1.2)
                band(along(cBlush, tm, bl), 0.9, 4, 0.92, ecx, ecy, 1.3)
            }
            // остриё: терракотовая точка даже у зелёного листа
            {
                const tip = Math.max(bl, 0.45 * (1 - y))
                const tx = PX(0, 1), ty = PY(1)
                const gb = ctx.createRadialGradient(tx, ty, 0, tx, ty, L * (0.05 + 0.1 * bl))
                gb.addColorStop(0, col(cBlush, 0.95 * tip))
                gb.addColorStop(0.45, col(cBlush, 0.5 * tip))
                gb.addColorStop(1, col(cBlush, 0))
                ctx.fillStyle = gb
                ctx.fillRect(0, 0, canvas.width, canvas.height)
            }

            // Градиент «от точки на краю»: линии равного цвета — эллипсы,
            // касающиеся в этой точке эллипса, который охватывает весь лист.
            // Так тень мягко нарастает к дальнему от света краю.
            const wx = hw * 1.22, wy = L * 0.6
            const wcx = cx + bend * L * 0.25, wcy = by - L * 0.5
            function sweep(dx, dy, stops) {
                const t = 0.97 / Math.sqrt(dx * dx / (wx * wx) + dy * dy / (wy * wy))
                ctx.save()
                ctx.translate(wcx, wcy)
                ctx.scale(wx, wy)
                const gr = ctx.createRadialGradient(dx * t / wx, dy * t / wy, 0, 0, 0, 1)
                for (const st of stops)
                    gr.addColorStop(st[0], st[1])
                ctx.fillStyle = gr
                ctx.fillRect(-1, -1, 2, 2)
                ctx.restore()
            }
            // сторона от света уходит в тень
            sweep(lx, ly, [[0, col(cDark, 0)], [0.36, col(cDark, 0)], [0.6, col(cDark, 0.14)],
                           [0.8, col(cDark, 0.36)], [1, col(cDark, 0.64)]])
            // сторона к свету чуть светлее
            sweep(-lx, -ly, [[0, col(cGlow, 0)], [0.45, col(cGlow, 0)], [0.8, col(cGlow, 0.14)], [1, col(cGlow, 0.3)]])

            // мягкий блик на выпуклости ближе к свету: лист толстый, с восковым налётом
            {
                ctx.save()
                ctx.translate(ecx + (lit[0] - ecx) * 0.42, ecy + (lit[1] - ecy) * 0.42)
                ctx.scale(ex, ey)
                const gs = ctx.createRadialGradient(0, 0, 0, 0, 0, 0.62)
                gs.addColorStop(0, col(cGlow, 0.2))
                gs.addColorStop(0.5, col(cGlow, 0.09))
                gs.addColorStop(1, col(cGlow, 0))
                ctx.fillStyle = gs
                ctx.fillRect(-1, -1, 2, 2)
                ctx.restore()
            }

            // складка по килю: едва заметный желобок вдоль середины
            {
                const t0 = Math.max(0.1, c * 0.9), t1 = 0.93
                const w = hw * 0.24
                const side = lx > 0 ? 1 : -1, power = 0.05 + 0.07 * Math.abs(lx)
                const gk = ctx.createLinearGradient(PX(0, tm) - w, 0, PX(0, tm) + w, 0)
                gk.addColorStop(0, col(cDark, 0))
                gk.addColorStop(0.5 - 0.1 * side, col(cGlow, power * 0.55))    // склон, обращённый к свету
                gk.addColorStop(0.5 + 0.07 * side, col(cDark, power))
                gk.addColorStop(1, col(cDark, 0))
                ctx.fillStyle = gk
                ctx.beginPath()
                ctx.moveTo(PX(0, t0), PY(t0))
                ctx.quadraticCurveTo(PX(0, tm) + w, PY(tm), PX(0, t1), PY(t1))
                ctx.quadraticCurveTo(PX(0, tm) - w, PY(tm), PX(0, t0), PY(t0))
                ctx.fill()
            }

            // край к свету светится: лист мясистый, воск рассеивает свет
            band(col(cGlow), 0.62, 5, 0.93, dark[0], dark[1], 1.5)

            ctx.restore()
        }
    }
}
