import QtQuick

// Процедурный седум в терракотовом горшке, вид сверху. Листья разложены
// по золотому углу (137.5°), как у настоящего растения: новые появляются
// в центре, старые уходят наружу, разрастаются и краснеют по краям.
//
// stage — стадия роста (страница установки: 0..7). Рост идёт пружиной.
// blooming — растение выпускает цветоносы с жёлтыми звёздочками.
//
// Каждый лист и цветок рисуется один раз в свою текстуру (см. Leaf, Bloom),
// поэтому анимация — только сдвиги, повороты и масштаб.
Item {
    id: root

    property real stage: 0
    property real size: 380
    property bool blooming: false
    property bool potted: true      // в горшке; false — одна розетка на бумаге
    property bool still: false      // без покачивания (для снимков и проверок)

    // Анимируемая стадия: за ней на пружине тянется вся розетка
    property real growth: stage
    Behavior on growth {
        id: growthBehavior
        SpringAnimation { spring: 1.4; damping: 0.2; epsilon: 0.002 }
    }

    // Показать рост «с прошлой стадии до текущей» — вызывается при показе страницы.
    // Цветущее растение заодно заново раскрывает цветы.
    function regrow(from) {
        growthBehavior.enabled = false
        growth = Math.max(0, from)
        growthBehavior.enabled = true
        growth = Qt.binding(function() { return root.stage })

        flowerMotion = false
        flowering = false
        flowerMotion = true
        flowering = Qt.binding(function() { return root.blooming })
    }

    width: size
    height: size

    // Текстуры листьев и цветов запекаются под стадию с шагом в полстадии:
    // плавная смена stage не заставляет перерисовывать их на каждом кадре.
    readonly property real bakedStage: Math.round(stage * 2) / 2
    // Запас разрешения текстур: на экранах с высокой плотностью он уже есть
    readonly property real quality: Screen.devicePixelRatio > 1.4 ? 1 : 1.5

    // Растение показывается целиком, когда нарисованы горшок и все листья:
    // текстуры готовятся в фоне, и иначе было бы видно, как они появляются по одной.
    property int readyLeaves: 0
    readonly property bool baked: (!potted || potItem.ready)
                                  && readyLeaves >= Math.min(maxLeaves, Math.ceil(leafCount(bakedStage)))
    property bool shown: false
    onBakedChanged: if (baked) shown = true
    // Страховка: если какая-то текстура не отчиталась, всё равно показаться.
    // Отсчёт идёт с первого рисования — у скрытой страницы оно ещё не началось.
    property bool painting: false
    Timer {
        interval: 700
        running: root.painting && !root.shown
        onTriggered: root.shown = true
    }

    // ---------- как растёт розетка
    readonly property int maxLeaves: 42
    readonly property real fullCount: leafCount(7)
    readonly property real radius: size * 0.435     // до кончиков листьев взрослого растения

    function leafCount(s) { return 9 + 4.4 * s }

    // Насколько далеко от центра кончик листа (доля radius) по возрасту
    function reach(age) {
        if (age <= 0)
            return 0
        return Math.pow((age + 3) / (fullCount + 3), 0.85) * (1 - Math.exp(-(age + 0.3) / 2.2))
    }
    // Ширина листа относительно длины: молодые стоят торчком и сверху
    // выглядят короткими и широкими
    function girth(age) { return 0.52 + 0.4 * Math.exp(-Math.max(0, age) / 4.5) }
    function youth(age) { return Math.exp(-Math.max(0, age) / 5) }

    function noise(i, salt) {
        const v = Math.sin(i * 12.9898 + salt * 78.233) * 43758.5453
        return v - Math.floor(v)
    }

    // Лист номер i (0 — самый старый): направление, длина и ширина в возрасте age
    function leafTurn(i) { return i * 137.508 + (noise(i, 1) - 0.5) * 9 }
    function leafLength(i, age) { return radius * reach(age) * (0.95 + 0.1 * noise(i, 2)) }
    function leafBreadth(i, age) { return leafLength(i, age) * girth(age) * (0.96 + 0.08 * noise(i, 3)) }

    // Лёгкий ветерок: розетка едва заметно поворачивается, по листьям идёт волна,
    // цветы на тонких стеблях качаются сильнее
    property real breeze: 0
    NumberAnimation on breeze {
        from: 0; to: 2 * Math.PI
        duration: 9000
        loops: Animation.Infinite
        running: !root.still
    }

    // ---------- цветение
    // Внутренний флаг, чтобы regrow() мог проиграть раскрытие заново
    property bool flowering: blooming
    property bool flowerMotion: true

    // Насколько растение сейчас меньше целевого размера (пока растёт)
    readonly property real grownShare: reach(leafCount(growth)) / reach(leafCount(bakedStage))

    // Листва как набор эллипсов, вписанных в пластинки взрослых листьев:
    // по ней соцветия ищут себе место, чтобы не свешиваться за листья.
    function foliageAt(s) {
        const count = leafCount(s), list = []
        for (let i = 0; i < maxLeaves; ++i) {
            const age = count - i
            if (age < 7)
                break
            const len = leafLength(i, age), t = leafTurn(i) * Math.PI / 180
            list.push({ sin: Math.sin(t), cos: Math.cos(t), mid: 0.6 * len, a: 0.46 * leafBreadth(i, age), b: 0.35 * len })
        }
        return list
    }
    function onFoliage(leaves, x, y) {      // x, y — от центра розетки
        for (const l of leaves) {
            const along = x * l.sin - y * l.cos - l.mid, across = x * l.cos + y * l.sin
            if (along * along / (l.b * l.b) + across * across / (l.a * l.a) <= 1)
                return true
        }
        return false
    }

    // Соцветие: раскрытые цветки по спирали вокруг конца стебля, между ними — бутоны.
    // Координаты — от конца стебля, в долях unit.
    function cluster(spec, order) {
        const list = []
        for (let i = 0; i < spec.blooms; ++i) {
            const a = i * 2.39996 + order * 1.7 + 0.6
            const r = 0.063 * Math.sqrt(i + 0.3)
            list.push({ dx: r * Math.sin(a), dy: -r * Math.cos(a), bud: false,
                        size: 0.18 - 0.004 * i + 0.02 * noise(i, order + 8),
                        turn: noise(i, order + 9) * 72 })
        }
        for (let i = 0; i < spec.buds; ++i) {
            const a = (spec.blooms - 1 - i * 2) * 2.39996 + order * 1.7 + 0.6 + 1.1
            const r = 0.063 * Math.sqrt(spec.blooms - 0.5) * (0.92 + 0.1 * noise(i, order + 5))
            list.push({ dx: r * Math.sin(a), dy: -r * Math.cos(a), bud: true,
                        size: 0.11 + 0.02 * noise(i, order + 7), turn: a * 180 / Math.PI })
        }
        return list
    }

    // Куда поставить соцветие: как можно дальше от центра, но чтобы каждый
    // цветок целиком лежал на листьях и не прятался под молодыми листьями центра.
    function placeSpray(spec, order) {
        const leaves = foliageAt(bakedStage)
        const full = radius * reach(leafCount(bakedStage))  // размер растения на этой стадии
        const inner = radius * reach(7.5) * 1.1             // ближе — молодые листья, они выше стебля
        let best = null
        for (let shrink = 1; shrink > 0.55 && !best; shrink *= 0.86) {
            const unit = full * shrink
            const flowers = cluster(spec, order)
            for (const offset of [0, 13, -13, 26, -26]) {
                const ang = (spec.turn + offset) * Math.PI / 180
                for (let to = spec.reach; to >= 0.3; to -= 0.03) {
                    const ex = Math.sin(ang) * to * full, ey = -Math.cos(ang) * to * full
                    let fits = true
                    for (const f of flowers) {
                        const x = ex + f.dx * unit, y = ey + f.dy * unit
                        const r = f.size * unit * (f.bud ? 0.34 : 0.5) + 0.012 * unit
                        if (Math.hypot(x, y) - r < inner || !onFoliage(leaves, x, y)) { fits = false; break }
                        for (let p = 0; p < 6 && fits; ++p)
                            fits = onFoliage(leaves, x + r * Math.cos(p * Math.PI / 3), y + r * Math.sin(p * Math.PI / 3))
                        if (!fits)
                            break
                    }
                    if (fits) {
                        if (!best || to > best.to + 0.045)
                            best = { ang: ang, to: to, unit: unit, full: full, flowers: flowers }
                        break
                    }
                }
                if (best && best.to >= spec.reach - 0.2)
                    break
            }
        }
        return best
    }

    // Тень растения на бумаге: когда розетка перерастает горшок, листья
    // висят высоко над столом, и тень от них такая же мягкая, как от горшка.
    // Пока растение меньше горшка, она целиком спрятана под ним.
    Canvas {
        id: plantShadow

        opacity: root.shown && root.potted ? 1 : 0
        x: (root.width - width) / 2
        y: (root.height - height) / 2
        width: Math.ceil(root.size * 1.24)
        height: width
        antialiasing: true
        renderStrategy: Canvas.Threaded
        transform: Scale {
            origin.x: plantShadow.width / 2; origin.y: plantShadow.height / 2
            xScale: root.reach(root.leafCount(root.growth)); yScale: xScale
        }

        onWidthChanged: Qt.callLater(requestPaint)
        onPaint: {
            root.painting = true
            const ctx = getContext("2d")
            ctx.reset()
            ctx.clearRect(0, 0, width, height)
            const r = root.radius, shift = root.size * 0.073
            const cx = width / 2 - Theme.lightX * shift, cy = height / 2 - Theme.lightY * shift
            const k = Theme.groundShadow
            const g = ctx.createRadialGradient(cx, cy, r * 0.55, cx, cy, r * 1.1)
            // слабее, чем у горшка: их тени накладываются, а темнее от этого быть не должно
            g.addColorStop(0, Qt.rgba(k.r, k.g, k.b, 0.17))
            g.addColorStop(0.55, Qt.rgba(k.r, k.g, k.b, 0.11))
            g.addColorStop(0.85, Qt.rgba(k.r, k.g, k.b, 0.035))
            g.addColorStop(1, Qt.rgba(k.r, k.g, k.b, 0))
            ctx.fillStyle = g
            ctx.fillRect(0, 0, width, height)
        }
    }

    Pot {
        id: potItem

        visible: root.potted
        opacity: root.shown ? 1 : 0
        quality: root.quality
        radius: root.size * 0.365
        x: root.width / 2 - width / 2
        y: root.height / 2 - height / 2
    }

    Item {
        id: rosette

        anchors.centerIn: parent
        width: root.size
        height: root.size
        rotation: 1.2 * Math.sin(root.breeze)
        opacity: root.shown ? 1 : 0

        Repeater {
            model: root.maxLeaves

            // index 0 — самый старый лист: внешний, рисуется первым
            delegate: Leaf {
                id: item

                // Лист запекается под целевую стадию, а движется за ростом
                readonly property real goal: root.leafCount(root.bakedStage) - index
                readonly property real age: root.leafCount(root.growth) - index
                readonly property real turn: root.leafTurn(index)

                visible: goal > 0 && age > 0
                z: index
                length: root.leafLength(index, goal)
                breadth: root.leafBreadth(index, goal)
                youth: root.youth(goal)
                blush: Math.max(0, Math.min(1, (goal - 12) / 22))
                azimuth: turn
                cover: goal > 9 ? root.reach(goal - 9) / root.reach(goal) * 0.92 : 0
                seed: index + 1
                quality: root.quality
                // за краем горшка листу не на что бросать тень
                hang: root.potted ? potItem.radius / Math.max(1, length) : 1
                onReadyChanged: root.readyLeaves += ready ? 1 : -1

                x: rosette.width / 2 - baseX
                y: rosette.height / 2 - baseY
                transform: [
                    Scale {
                        origin.x: item.baseX; origin.y: item.baseY
                        xScale: item.goal > 0 ? root.reach(item.age) * root.girth(item.age) / (root.reach(item.goal) * root.girth(item.goal)) : 0
                        yScale: item.goal > 0 ? root.reach(item.age) / root.reach(item.goal) : 0
                    },
                    Rotation {
                        origin.x: item.baseX; origin.y: item.baseY
                        angle: item.turn + 0.4 * Math.sin(2 * root.breeze + item.turn * Math.PI / 180)
                    }
                ]
            }
        }

        // ---------- цветоносы: выходят из-под молодых листьев и несут соцветия
        // над взрослыми. За пределы листвы не выходят (см. placeSpray).
        Repeater {
            // turn — куда клонится, reach — как далеко может уйти (доля размера растения),
            // start — на сколько градусов в сторону от этого направления стебель выходит
            // из середины, bow — изгиб
            model: [
                { turn: 48, reach: 0.78, start: -34, bow: 0.2, blooms: 7, buds: 3 },
                { turn: 168, reach: 0.6, start: 30, bow: -0.16, blooms: 5, buds: 2 },
                { turn: 286, reach: 0.7, start: -26, bow: 0.18, blooms: 6, buds: 3 }
            ]

            delegate: Item {
                id: spray

                readonly property int order: index
                readonly property var place: root.blooming ? root.placeSpray(modelData, index) : null
                readonly property real unit: place ? place.unit : 1
                readonly property real cx: rosette.width / 2
                readonly property real cy: rosette.height / 2

                // стебель: от основания b через колено k к соцветию e (координаты розетки)
                readonly property real dirX: place ? Math.sin(place.ang) : 0
                readonly property real dirY: place ? -Math.cos(place.ang) : -1
                readonly property real far: place ? place.to * place.full : 0
                readonly property real near: place ? place.full * 0.13 : 0
                readonly property real startAng: place ? place.ang + modelData.start * Math.PI / 180 : 0
                readonly property real bx: cx + Math.sin(startAng) * near
                readonly property real by: cy - Math.cos(startAng) * near
                readonly property real ex: cx + dirX * far
                readonly property real ey: cy + dirY * far
                readonly property real kx: (bx + ex) / 2 - dirY * modelData.bow * (far - near)
                readonly property real ky: (by + ey) / 2 + dirX * modelData.bow * (far - near)

                readonly property var flowers: {
                    const list = []
                    if (place) {
                        for (const f of place.flowers)
                            list.push({ x: ex + f.dx * unit, y: ey + f.dy * unit, size: f.size * unit, bud: f.bud, turn: f.turn })
                    }
                    return list
                }

                // Стебель рисуется под молодыми листьями, но над всеми, что старше
                z: root.leafCount(root.bakedStage) - 7.5

                property real grow: root.flowering ? 1 : 0
                Behavior on grow {
                    enabled: root.flowerMotion
                    SequentialAnimation {
                        PauseAnimation { duration: 40 + 80 * spray.order }
                        SpringAnimation { spring: 4; damping: 0.3; epsilon: 0.003 }
                    }
                }

                visible: place !== null && grow > 0.001
                transform: [
                    Scale { origin.x: spray.bx; origin.y: spray.by; xScale: spray.grow; yScale: spray.grow },
                    Rotation { origin.x: spray.bx; origin.y: spray.by; angle: 1.4 * Math.sin(root.breeze + spray.order * 2.4) },
                    Scale { origin.x: spray.cx; origin.y: spray.cy; xScale: root.grownShare; yScale: root.grownShare }
                ]

                // стебель с цветоножками
                Canvas {
                    id: stalk

                    readonly property real q: root.quality
                    // прямоугольник, в который помещаются стебель и цветоножки
                    readonly property real x0: Math.min(spray.bx, spray.ex, spray.kx) - spray.unit * 0.3
                    readonly property real y0: Math.min(spray.by, spray.ey, spray.ky) - spray.unit * 0.3
                    readonly property real x1: Math.max(spray.bx, spray.ex, spray.kx) + spray.unit * 0.3
                    readonly property real y1: Math.max(spray.by, spray.ey, spray.ky) + spray.unit * 0.3

                    x: x0
                    y: y0
                    z: -1000
                    width: Math.ceil((x1 - x0) * q)
                    height: Math.ceil((y1 - y0) * q)
                    scale: 1 / q
                    transformOrigin: Item.TopLeft
                    antialiasing: true
                    smooth: true
                    renderStrategy: Canvas.Threaded

                    readonly property var baked: [spray.unit, spray.flowers]
                    onBakedChanged: Qt.callLater(requestPaint)

                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.reset()
                        ctx.clearRect(0, 0, width, height)
                        if (!spray.place)
                            return
                        const u = spray.unit * q
                        const P = (x, y) => [(x - x0) * q, (y - y0) * q]
                        const b = P(spray.bx, spray.by), k = P(spray.kx, spray.ky), e = P(spray.ex, spray.ey)
                        const lx = Theme.lightX, ly = Theme.lightY
                        const rgb = c => [c.r, c.g, c.b]
                        const col = (c, a) => Qt.rgba(c[0], c[1], c[2], a === undefined ? 1 : a)
                        const cast = rgb(Theme.groundShadow)
                        const stem = rgb(Theme.flowerStalk), stemLight = rgb(Theme.flowerStalkLight)
                        const stemDark = rgb(Theme.flowerStalkDark)

                        const at = t => [(1 - t) * (1 - t) * b[0] + 2 * t * (1 - t) * k[0] + t * t * e[0],
                                         (1 - t) * (1 - t) * b[1] + 2 * t * (1 - t) * k[1] + t * t * e[1]]
                        // стебель сужается к соцветию: рисуем полосой переменной ширины
                        function ribbon(w0, w1, dx, dy, lift) {
                            const n = 18, leftSide = [], rightSide = []
                            for (let i = 0; i <= n; ++i) {
                                const t = i / n
                                const p = at(t), p2 = at(Math.min(1, t + 0.01)), p1 = at(Math.max(0, t - 0.01))
                                let nx = -(p2[1] - p1[1]), ny = p2[0] - p1[0]
                                const len = Math.hypot(nx, ny) || 1
                                nx /= len; ny /= len
                                const w = (w0 + (w1 - w0) * t) / 2
                                const ox = dx * (lift ? t : 1), oy = dy * (lift ? t : 1)
                                leftSide.push([p[0] + nx * w + ox, p[1] + ny * w + oy])
                                rightSide.push([p[0] - nx * w + ox, p[1] - ny * w + oy])
                            }
                            ctx.beginPath()
                            ctx.moveTo(leftSide[0][0], leftSide[0][1])
                            for (const p of leftSide) ctx.lineTo(p[0], p[1])
                            for (let i = n; i >= 0; --i) ctx.lineTo(rightSide[i][0], rightSide[i][1])
                            ctx.closePath()
                        }
                        const w0 = u * 0.04, w1 = u * 0.022
                        const fl = spray.flowers.map(f => P(f.x, f.y))

                        // тень: стебель приподнят над листьями, к соцветию — выше
                        const h = u * 0.06
                        for (let i = 1; i <= 4; ++i) {
                            ribbon(w0 + i * q, w1 + i * q, -lx * h, -ly * h, true)
                            ctx.fillStyle = col(cast, 0.08)
                            ctx.fill()
                        }

                        // цветоножки: короткие развилки на конце стебля, дальше их прячут цветки
                        ctx.lineCap = "round"
                        const hx = lx * u * 0.004, hy = ly * u * 0.004
                        for (const pass of [0, 1]) {
                            ctx.strokeStyle = pass ? col(stemLight, 0.85) : col(stemDark)
                            ctx.lineWidth = u * (pass ? 0.008 : 0.017)
                            for (const f of fl) {
                                ctx.beginPath()
                                ctx.moveTo(e[0] + pass * hx, e[1] + pass * hy)
                                ctx.lineTo(e[0] + (f[0] - e[0]) * 0.6 + pass * hx, e[1] + (f[1] - e[1]) * 0.6 + pass * hy)
                                ctx.stroke()
                            }
                        }

                        // стебель: тёмный край, тело, свет со стороны света
                        ribbon(w0, w1, 0, 0, false)
                        ctx.fillStyle = col(stemDark)
                        ctx.fill()
                        const g = ctx.createLinearGradient(b[0], b[1], e[0], e[1])
                        g.addColorStop(0, col(stemDark))
                        g.addColorStop(0.3, col(stem))
                        g.addColorStop(1, col(stemLight))
                        ribbon(w0 * 0.72, w1 * 0.72, lx * w0 * 0.12, ly * w0 * 0.12, false)
                        ctx.fillStyle = g
                        ctx.fill()
                        ribbon(w0 * 0.22, w1 * 0.22, lx * w0 * 0.24, ly * w0 * 0.24, false)
                        ctx.fillStyle = col([1, 1, 1], 0.32)
                        ctx.fill()
                    }
                }

                Repeater {
                    model: spray.flowers

                    delegate: Bloom {
                        size: modelData.size
                        bud: modelData.bud
                        turn: modelData.turn
                        seed: index * 7 + spray.order * 31 + 1
                        quality: root.quality * 4 / 3
                        x: modelData.x - width / 2
                        y: modelData.y - height / 2
                        // бутоны выглядывают из-под цветков, середина соцветия — поверх
                        z: modelData.bud ? -100 - index : -index

                        scale: root.flowering ? 1 : 0
                        rotation: 4 * Math.sin(root.breeze * 2 + index * 1.9)
                        Behavior on scale {
                            enabled: root.flowerMotion
                            SequentialAnimation {
                                PauseAnimation { duration: 240 + 80 * spray.order + 40 * index }
                                SpringAnimation { spring: 5; damping: 0.3; epsilon: 0.005 }
                            }
                        }
                    }
                }
            }
        }
    }
}
