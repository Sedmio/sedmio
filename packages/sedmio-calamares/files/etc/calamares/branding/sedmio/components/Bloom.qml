import QtQuick

// Цветок седума, вид сверху: звёздочка из пяти острых лепестков с желобком,
// в середине — завязь и тычинки с тёмными пыльниками. bud — нераскрытый бутон.
// Как и лист, рисуется один раз в текстуру; свет — тот же, что у растения.
Item {
    id: bloom

    property real size: 28          // размах лепестков, px
    property bool bud: false
    property real turn: 0           // поворот цветка на экране, градусы
    property real seed: 0
    property real quality: 2

    property bool ready: false

    readonly property real pad: Math.ceil(size * 0.3 + 2)

    width: Math.ceil(size + 2 * pad)
    height: width

    readonly property var baked: [size, bud, turn, seed, quality]
    onBakedChanged: Qt.callLater(canvas.requestPaint)

    Canvas {
        id: canvas

        width: Math.ceil(bloom.width * bloom.quality)
        height: width
        scale: 1 / bloom.quality
        transformOrigin: Item.TopLeft
        antialiasing: true
        smooth: true
        renderStrategy: Canvas.Threaded

        opacity: bloom.ready ? 1 : 0
        onPainted: bloom.ready = true

        function noise(salt) {
            const v = Math.sin(bloom.seed * 12.9898 + salt * 78.233) * 43758.5453
            return v - Math.floor(v)
        }
        function rgb(c) { return [c.r, c.g, c.b] }
        function mix(a, b, t) { return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t] }
        function col(c, a) { return Qt.rgba(c[0], c[1], c[2], a === undefined ? 1 : a) }

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            ctx.clearRect(0, 0, width, height)

            const q = bloom.quality
            const c = width / 2
            const r = bloom.size * q / 2
            const lx = Theme.lightX, ly = Theme.lightY
            const spin = bloom.turn * Math.PI / 180

            const deep = rgb(Theme.flowerDeep), gold = rgb(Theme.flower)
            const light = rgb(Theme.flowerLight), pale = rgb(Theme.flowerPale)
            const heart = rgb(Theme.flowerHeart), anther = rgb(Theme.flowerAnther)
            const cast = rgb(Theme.groundShadow)

            // ----- тень: цветок висит над листьями, поэтому она мягкая и в стороне
            {
                const d = r * (bloom.bud ? 0.3 : 0.42)
                const rr = r * (bloom.bud ? 0.62 : 1.0)
                const g = ctx.createRadialGradient(c - lx * d, c - ly * d, 0, c - lx * d, c - ly * d, rr)
                g.addColorStop(0, col(cast, 0.34))
                g.addColorStop(0.55, col(cast, 0.2))
                g.addColorStop(1, col(cast, 0))
                ctx.fillStyle = g
                ctx.fillRect(0, 0, width, height)
            }

            if (bloom.bud) {
                // бутон: плотная капля, сложенные лепестки видны швами
                const len = r * 0.6, wid = r * 0.46
                ctx.save()
                ctx.translate(c, c)
                ctx.rotate(spin)
                const body = () => {
                    ctx.beginPath()
                    ctx.moveTo(0, len)
                    ctx.bezierCurveTo(wid * 1.1, len * 0.9, wid * 1.15, -len * 0.25, 0, -len)
                    ctx.bezierCurveTo(-wid * 1.15, -len * 0.25, -wid * 1.1, len * 0.9, 0, len)
                    ctx.closePath()
                }
                const g = ctx.createLinearGradient(0, len, 0, -len)
                g.addColorStop(0, col(rgb(Theme.flowerBud)))
                g.addColorStop(0.55, col(mix(rgb(Theme.flowerBud), gold, 0.6)))
                g.addColorStop(1, col(light))
                body()
                ctx.fillStyle = g
                ctx.fill()
                ctx.save()
                body()
                ctx.clip()
                // объём: тень со стороны от света, блик — со стороны света
                const ux = lx * Math.cos(spin) + ly * Math.sin(spin)
                const uy = -lx * Math.sin(spin) + ly * Math.cos(spin)
                const gs = ctx.createRadialGradient(ux * wid * 0.5, uy * len * 0.5, 0, 0, 0, len * 1.2)
                gs.addColorStop(0, col(pale, 0.5))
                gs.addColorStop(0.35, col(pale, 0))
                gs.addColorStop(0.7, col(deep, 0.25))
                gs.addColorStop(1, col(rgb(Theme.flowerBud), 0.7))
                ctx.fillStyle = gs
                ctx.fillRect(-r, -r, 2 * r, 2 * r)
                // швы
                ctx.strokeStyle = col(rgb(Theme.flowerBud), 0.55)
                ctx.lineWidth = Math.max(0.6, r * 0.035)
                ctx.beginPath()
                ctx.moveTo(-wid * 0.2, len * 0.8)
                ctx.quadraticCurveTo(-wid * 0.45, 0, 0, -len)
                ctx.moveTo(wid * 0.2, len * 0.8)
                ctx.quadraticCurveTo(wid * 0.45, 0, 0, -len)
                ctx.stroke()
                ctx.restore()
                ctx.restore()
                return
            }

            // ----- лепестки
            const petal = (len, wid, grow) => {
                const hw = wid / 2 + grow
                ctx.beginPath()
                ctx.moveTo(0, grow)
                ctx.bezierCurveTo(hw * 0.9, -len * 0.08, hw * 1.05, -len * 0.38, hw * 0.78, -len * 0.62)
                ctx.quadraticCurveTo(hw * 0.4, -len * 0.9, 0, -len - grow)
                ctx.quadraticCurveTo(-hw * 0.4, -len * 0.9, -hw * 0.78, -len * 0.62)
                ctx.bezierCurveTo(-hw * 1.05, -len * 0.38, -hw * 0.9, -len * 0.08, 0, grow)
                ctx.closePath()
            }
            for (let i = 0; i < 5; ++i) {
                const ang = spin + i * 2 * Math.PI / 5 + (noise(i + 1) - 0.5) * 0.2
                const len = r * (0.92 + 0.1 * noise(i + 11))
                const wid = len * 0.46
                // свет в осях лепестка
                const ux = lx * Math.cos(ang) + ly * Math.sin(ang)
                const uy = -lx * Math.sin(ang) + ly * Math.cos(ang)

                ctx.save()
                ctx.translate(c, c)
                ctx.rotate(ang)
                // тёмный край: лепестки отделяются друг от друга
                petal(len, wid, Math.max(0.5, r * 0.035))
                ctx.fillStyle = col(deep, 0.75)
                ctx.fill()

                const g = ctx.createLinearGradient(0, 0, 0, -len)
                g.addColorStop(0, col(deep))
                g.addColorStop(0.3, col(gold))
                g.addColorStop(0.75, col(light))
                g.addColorStop(1, col(pale))
                petal(len, wid, 0)
                ctx.fillStyle = g
                ctx.fill()

                // желобок: половина к свету светлее, другая темнее; кончик смотрит на свет — ярче
                ctx.save()
                petal(len, wid, 0)
                ctx.clip()
                const side = ux > 0 ? 1 : -1
                const gh = ctx.createLinearGradient(-wid / 2, 0, wid / 2, 0)
                gh.addColorStop(side > 0 ? 0 : 1, col(deep, 0.1 + 0.3 * Math.abs(ux)))
                gh.addColorStop(0.5 - 0.02 * side, col(deep, 0.05 + 0.2 * Math.abs(ux)))
                gh.addColorStop(0.5 + 0.04 * side, col(pale, 0.3 + 0.3 * Math.abs(ux)))
                gh.addColorStop(side > 0 ? 1 : 0, col(pale, 0.05))
                ctx.fillStyle = gh
                ctx.fillRect(-wid, -len * 1.1, 2 * wid, len * 1.2)
                if (uy > 0) {       // лепесток смотрит от света: чуть глуше
                    ctx.fillStyle = col(deep, 0.16 * uy)
                    ctx.fillRect(-wid, -len * 1.1, 2 * wid, len * 1.2)
                }
                ctx.restore()
                ctx.restore()
            }

            // ----- середина: глубина, завязь, тычинки
            {
                const g = ctx.createRadialGradient(c, c, 0, c, c, r * 0.42)
                g.addColorStop(0, col(heart, 0.85))
                g.addColorStop(0.5, col(heart, 0.45))
                g.addColorStop(1, col(heart, 0))
                ctx.fillStyle = g
                ctx.fillRect(c - r, c - r, 2 * r, 2 * r)
            }
            // тычинки: по одной между лепестками и по одной на лепестке
            ctx.lineCap = "round"
            for (let i = 0; i < 10; ++i) {
                const ang = spin + i * Math.PI / 5 + (noise(i + 21) - 0.5) * 0.25
                const reachOut = r * (i % 2 ? 0.5 : 0.4) * (0.9 + 0.2 * noise(i + 31))
                const ex = c + Math.sin(ang) * reachOut, ey = c - Math.cos(ang) * reachOut
                ctx.strokeStyle = col(pale, 0.9)
                ctx.lineWidth = Math.max(0.5, r * 0.03)
                ctx.beginPath()
                ctx.moveTo(c + Math.sin(ang) * r * 0.1, c - Math.cos(ang) * r * 0.1)
                ctx.lineTo(ex, ey)
                ctx.stroke()
                ctx.fillStyle = col(anther)
                ctx.beginPath()
                ctx.arc(ex, ey, Math.max(0.7, r * 0.055), 0, 2 * Math.PI)
                ctx.fill()
            }
            // завязь: пять зеленоватых долек звёздочкой
            for (let i = 0; i < 5; ++i) {
                const ang = spin + (i + 0.5) * 2 * Math.PI / 5
                ctx.save()
                ctx.translate(c, c)
                ctx.rotate(ang)
                petal(r * 0.24, r * 0.13, 0)
                ctx.fillStyle = col(rgb(Theme.flowerCarpel))
                ctx.fill()
                ctx.restore()
            }
        }
    }
}
