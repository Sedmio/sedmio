import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import Sedmio.Style

// Рамка вокруг экрана и панели — по макету (DesktopLayout):
//   "left"    — рамка со скруглённым проёмом, слева в неё встроена панель
//               (Bar). Запуск программ выезжает сверху слева, панель
//               управления — снизу слева, у часов;
//   "dock"    — сверху панель (TopBar), снизу док по центру (Dock), рамки
//               по бокам и снизу нет. Запуск — карточкой над доком;
//   "taskbar" — сверху панель, снизу панель задач (Taskbar) на всю ширину.
//               Запуск выезжает из неё снизу слева.
// Во всех: уведомления и ход копирования файлов — сверху справа, буфер
// обмена — сверху посередине. С верхней панелью панель управления выезжает
// сверху справа, календарь — сверху посередине, под часами. Индикатор
// громкости и яркости — снизу посередине (в доке — сверху).
// Одно окно на весь экран поверх программ: рисовать можно где угодно,
// а мышь окно ловит только на рамке, доке и уведомлениях (mask), остальное
// уходит окнам под ним. Пока открыт запуск, панель управления или центр
// уведомлений — весь экран: клик мимо закрывает.
PanelWindow {
    id: frame
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "sedmio-frame"
    WlrLayershell.keyboardFocus: anyOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // Экрана может не быть, пока окно пересоздаётся (перезагрузка QML,
    // экран отключили): тогда здесь ничего не открыто.
    readonly property string screenName: screen ? screen.name : ""
    function isHere(name) { return screenName !== "" && name === screenName; }

    readonly property bool launcherOpen: isHere(ShellState.launcherScreen)
    readonly property bool controlOpen: isHere(ShellState.controlScreen)
    readonly property bool centerOpen: isHere(ShellState.centerScreen)
    readonly property bool panelOpen: isHere(ShellState.panelScreen)
    readonly property bool quickMenuOpen: isHere(ShellState.quickMenuScreen)
    readonly property bool anyOpen: launcherOpen || controlOpen || centerOpen || panelOpen || quickMenuOpen

    // ── Док ─────────────────────────────────────────────────────────────
    // Прячется, пока на этом экране развёрнуто окно (или во весь экран):
    // тогда окно занимает всю высоту. Мышь к нижнему краю — док выезжает;
    // ушла — прячется через полсекунды. Пока открыт запуск или меню из
    // дока — не прячется.
    readonly property bool dockCovered: {
        if (!DesktopLayout.dock) return false;
        for (const t of ToplevelManager.toplevels.values) {
            if (t.minimized || t.inCurrentDesktop === false || !(t.maximized || t.fullscreen)) continue;
            if (t.screens.some(s => s?.name === frame.screenName)) return true;
        }
        return false;
    }
    property bool dockHeld: false
    Timer {
        id: dockRelease
        interval: 500
        onTriggered: frame.dockHeld = dockHover.hovered || revealHover.hovered
    }
    function dockHoverChanged() {
        if (dockHover.hovered || revealHover.hovered) {
            dockRelease.stop();
            dockHeld = true;
        } else {
            dockRelease.restart();
        }
    }
    readonly property bool dockShown: DesktopLayout.dock
        && (!dockCovered || dockHeld || launcherOpen || quickMenuOpen || ShellState.panelMenus > 0)
    property real dockProgress: dockShown ? 1 : 0
    Behavior on dockProgress {
        NumberAnimation {
            duration: frame.dockShown ? Motion.springDuration : Theme.animNormal
            easing.type: frame.dockShown ? Easing.BezierSpline : Easing.OutCubic
            easing.bezierCurve: Motion.spring
        }
    }
    readonly property real dockWidth: dockLoader.item ? dockLoader.item.implicitWidth : 0
    readonly property real dockX: Math.round(frame.width / 2 - dockWidth / 2)
    // Верх дока, когда он выехал (по нему ставятся запуск и меню).
    readonly property real dockTop: frame.height - DesktopLayout.dockMargin - DesktopLayout.dockHeight
    readonly property real dockY: dockTop + (1 - dockProgress) * (DesktopLayout.dockHeight + DesktopLayout.dockMargin + 16)

    // ── Запуск программ ─────────────────────────────────────────────────
    // 0 — запуск спрятан в рамке, 1 — выехал полностью.
    property real launcherProgress: launcherOpen ? 1 : 0
    Behavior on launcherProgress {
        NumberAnimation {
            // Выезжает с пружинкой, уезжает быстро и без неё.
            duration: frame.launcherOpen ? Motion.springDuration : Theme.animFast + 40
            easing.type: frame.launcherOpen ? Easing.BezierSpline : Easing.InCubic
            easing.bezierCurve: Motion.spring
        }
    }
    readonly property real launcherWidth: 480
    // Высота запуска по содержимому; меняется плавно.
    readonly property real launcherMaxHeight: Math.min(hole.height - 120, 620)
    property real launcherHeight: launcher.wantedHeight + 26
    Behavior on launcherHeight {
        enabled: frame.launcherProgress === 1
        NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic }
    }
    // Слева — из угла сверху; с панелью задач — из неё, снизу слева;
    // с доком — карточкой над ним.
    readonly property real launcherX: DesktopLayout.left ? DesktopLayout.insetLeft
        : DesktopLayout.taskbar ? 6 : Math.round(frame.width / 2 - launcherWidth / 2)
    // Нижний край запуска, выезжающего снизу.
    readonly property real launcherBottom: DesktopLayout.taskbar ? frame.height - DesktopLayout.insetBottom : dockTop - 10
    // Где запуск, когда выехал полностью.
    readonly property real launcherY: DesktopLayout.left ? DesktopLayout.insetTop : launcherBottom - launcherHeight

    // ── Панель управления ───────────────────────────────────────────────
    property real controlProgress: controlOpen ? 1 : 0
    Behavior on controlProgress {
        NumberAnimation {
            // Выезжает с пружинкой, уезжает быстро и без неё.
            duration: frame.controlOpen ? Motion.springDuration : Theme.animFast + 40
            easing.type: frame.controlOpen ? Easing.BezierSpline : Easing.InCubic
            easing.bezierCurve: Motion.spring
        }
    }
    readonly property real controlWidth: 400
    property real controlHeight: control.wantedHeight + 28
    Behavior on controlHeight {
        enabled: frame.controlProgress === 1
        NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic }
    }
    // "bottomLeft" (полоса слева), "topRight" (под кнопками верхней
    // панели), "topCenter" (календарь под часами верхней панели).
    readonly property string controlPlace: DesktopLayout.left ? "bottomLeft"
        : ShellState.controlSection === "calendar" ? "topCenter" : "topRight"
    readonly property real controlX: controlPlace === "bottomLeft" ? DesktopLayout.insetLeft
        : controlPlace === "topCenter" ? Math.round(frame.width / 2 - controlWidth / 2)
        : frame.width - DesktopLayout.insetRight - controlWidth
    readonly property real controlY: controlPlace === "bottomLeft"
        ? frame.height - DesktopLayout.insetBottom - controlHeight : DesktopLayout.insetTop

    // ── Шторка модуля (буфер обмена): из верхней полосы посередине ──────
    property real panelProgress: panelOpen ? 1 : 0
    Behavior on panelProgress {
        NumberAnimation {
            // Выезжает с пружинкой, уезжает быстро и без неё.
            duration: frame.panelOpen ? Motion.springDuration : Theme.animFast + 40
            easing.type: frame.panelOpen ? Easing.BezierSpline : Easing.InCubic
            easing.bezierCurve: Motion.spring
        }
    }
    // Модуль шторки: последний открытый — пока она уезжает, в ней то же.
    property string panelModule: ""
    Connections {
        target: ShellState
        function onPanelModuleChanged() { if (ShellState.panelModule !== "") frame.panelModule = ShellState.panelModule; }
    }
    Component.onCompleted: panelModule = ShellState.panelModule
    readonly property real panelWidth: Math.min(Modules.manifests[panelModule]?.panelWidth ?? 580, hole.width - 120)
    property real panelHeight: (panel.item ? panel.item.wantedHeight : 0) + 28
    Behavior on panelHeight {
        enabled: frame.panelProgress === 1
        NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic }
    }

    // ── Уведомления и индикатор ─────────────────────────────────────────
    // Уведомления и индикатор — на экране, с которым сейчас работают.
    // Пока открыт центр уведомлений (на любом экране), карточки не всплывают;
    // с верхней панелью — и пока открыта панель управления: она на их месте.
    readonly property bool isFocusedScreen: isHere(ShellState.focusedScreen())
    // Карточки операций (копирование файлов) — там же, над уведомлениями.
    readonly property bool notificationsShown: isFocusedScreen
        && ((popups.item ? popups.item.count : 0) > 0 || JobsState.popups.length > 0)
        && ShellState.centerScreen === ""
        && !(controlOpen && controlPlace === "topRight")
    readonly property bool osdShown: OsdState.shown && isHere(OsdState.screenName)

    // Справа сверху один выдвижной ящик: в нём либо всплывающие карточки,
    // либо центр уведомлений. Уведомления — модуль: карточки — его часть
    // "popups", центр — "center"; выключен — остаются карточки операций.
    readonly property real notificationsWidth: 400
    property real notificationsHeight: centerOpen ? (center.item ? center.item.wantedHeight : 0) + 28
        : notificationsShown ? notifications.implicitHeight + 20 : 0
    Behavior on notificationsHeight { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }

    property real osdProgress: osdShown ? 1 : 0
    Behavior on osdProgress {
        NumberAnimation {
            duration: frame.osdShown ? Motion.springDuration : Theme.animNormal
            easing.type: frame.osdShown ? Easing.BezierSpline : Easing.OutCubic
            easing.bezierCurve: Motion.spring
        }
    }
    property real osdWidth: osd.wantedWidth
    Behavior on osdWidth { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
    // С доком индикатор сверху: внизу док.
    readonly property bool osdOnTop: DesktopLayout.dock

    // ── Меню Win+X — карточкой у знака Sedmio ───────────────────────────
    readonly property real quickMenuX: DesktopLayout.left ? DesktopLayout.insetLeft + 6
        : DesktopLayout.taskbar ? 6 : dockX
    readonly property real quickMenuY: DesktopLayout.left ? DesktopLayout.insetTop + 2
        : DesktopLayout.taskbar ? frame.height - DesktopLayout.insetBottom - quickMenu.height - 6
        : dockTop - quickMenu.height - 8

    // ── Стекло ──────────────────────────────────────────────────────────
    // Бумага рамки полупрозрачна (Theme.glassOpacity), под ней KWin
    // размывает то, что позади: панели, док, выехавшие ящики, меню Win+X.
    // Ящики — прямоугольниками со скруглёнными свободными углами, плюс
    // вогнутые «плечи», которыми ящик пристаёт к рамке (ShoulderRegion —
    // по их точной форме). Тема без стекла (glassOpacity 1) — размытия
    // нет: под непрозрачным его не видно.
    readonly property real glass: Theme.glassOpacity ?? 1
    BackgroundEffect.blurRegion: glass < 1 ? blurArea : null

    // Прямоугольник элемента в окне — с масштабом и сдвигом его анимации.
    function sceneBox(item) {
        const p = item.mapToItem(null, 0, 0);
        const q = item.mapToItem(null, item.width, item.height);
        return Qt.rect(p.x, p.y, q.x - p.x, q.y - p.y);
    }

    Region {
        id: blurArea
        item: content
        Region { item: hole; radius: DesktopLayout.holeRadius; intersection: Intersection.Subtract }

        // Док.
        Region {
            intersection: Intersection.Combine
            x: frame.dockX
            y: frame.dockY
            width: frame.dockProgress > 0 ? frame.dockWidth : 0
            height: frame.dockProgress > 0 ? DesktopLayout.dockHeight : 0
            radius: Theme.frameRadius
        }
        // Запуск: из угла сверху (полоса слева), из панели задач, над доком.
        Region {
            readonly property real h: frame.launcherHeight * frame.launcherProgress
            intersection: Intersection.Combine
            x: frame.launcherX
            y: DesktopLayout.left ? DesktopLayout.insetTop : frame.launcherBottom - h
            width: h > 0.5 ? frame.launcherWidth : 0
            height: h > 0.5 ? h : 0
            topLeftRadius: DesktopLayout.left ? 0 : Theme.frameRadius
            topRightRadius: DesktopLayout.left ? 0 : Theme.frameRadius
            bottomLeftRadius: DesktopLayout.dock ? Theme.frameRadius : 0
            bottomRightRadius: DesktopLayout.taskbar ? 0 : Theme.frameRadius
        }
        // Панель управления и календарь.
        Region {
            readonly property real h: frame.controlHeight * frame.controlProgress
            readonly property bool fromBottom: frame.controlPlace === "bottomLeft"
            intersection: Intersection.Combine
            x: frame.controlX
            y: fromBottom ? frame.height - DesktopLayout.insetBottom - h : DesktopLayout.insetTop
            width: h > 0.5 ? frame.controlWidth : 0
            height: h > 0.5 ? h : 0
            topLeftRadius: 0
            topRightRadius: fromBottom ? Theme.frameRadius : 0
            bottomLeftRadius: fromBottom ? 0 : Theme.frameRadius
            bottomRightRadius: frame.controlPlace === "topCenter" ? Theme.frameRadius : 0
        }
        // Уведомления и их центр.
        Region {
            intersection: Intersection.Combine
            x: frame.width - DesktopLayout.insetRight - frame.notificationsWidth
            y: DesktopLayout.insetTop
            width: frame.notificationsHeight > 0.5 ? frame.notificationsWidth : 0
            height: frame.notificationsHeight > 0.5 ? frame.notificationsHeight : 0
            bottomLeftRadius: Theme.frameRadius
        }
        // Шторка модуля (буфер обмена).
        Region {
            readonly property real h: frame.panelHeight * frame.panelProgress
            intersection: Intersection.Combine
            x: hole.x + hole.width / 2 - frame.panelWidth / 2
            y: DesktopLayout.insetTop
            width: h > 0.5 ? frame.panelWidth : 0
            height: h > 0.5 ? h : 0
            bottomLeftRadius: Theme.frameRadius
            bottomRightRadius: Theme.frameRadius
        }
        // Индикатор громкости и яркости.
        Region {
            readonly property real h: 54 * frame.osdProgress
            intersection: Intersection.Combine
            x: hole.x + hole.width / 2 - frame.osdWidth / 2
            y: frame.osdOnTop ? DesktopLayout.insetTop : frame.height - DesktopLayout.insetBottom - h
            width: h > 0.5 ? frame.osdWidth : 0
            height: h > 0.5 ? h : 0
            topLeftRadius: frame.osdOnTop ? 0 : Theme.frameRadius
            topRightRadius: frame.osdOnTop ? 0 : Theme.frameRadius
            bottomLeftRadius: frame.osdOnTop ? Theme.frameRadius : 0
            bottomRightRadius: frame.osdOnTop ? Theme.frameRadius : 0
        }
        // Плечи ящиков. DrawerShape (x0, y0, ширина w, высота h): плечо
        // справа сверху и слева снизу; EdgeDrawerShape (от края edgeY):
        // слева и справа у края. Отражённые ящики — отражёнными плечами.
        // Запуск: из угла сверху (полоса слева)…
        ShoulderRegion {
            readonly property real h: DesktopLayout.left ? frame.launcherHeight * frame.launcherProgress : 0
            f: h > 0.5 ? Math.min(Theme.frameRadius, h / 2) : 0
            sx: DesktopLayout.insetLeft + frame.launcherWidth; sy: DesktopLayout.insetTop
            cx: sx + f; cy: sy + f
        }
        ShoulderRegion {
            readonly property real h: DesktopLayout.left ? frame.launcherHeight * frame.launcherProgress : 0
            f: h > 0.5 ? Math.min(Theme.frameRadius, h / 2) : 0
            sx: DesktopLayout.insetLeft; sy: DesktopLayout.insetTop + h
            cx: sx + f; cy: sy + f
        }
        // …и из панели задач снизу.
        ShoulderRegion {
            readonly property real h: DesktopLayout.taskbar ? frame.launcherHeight * frame.launcherProgress : 0
            f: h > 0.5 ? Math.min(Theme.frameRadius, h) : 0
            sx: frame.launcherX - f; sy: frame.launcherBottom - f
            cx: sx; cy: sy
        }
        ShoulderRegion {
            readonly property real h: DesktopLayout.taskbar ? frame.launcherHeight * frame.launcherProgress : 0
            f: h > 0.5 ? Math.min(Theme.frameRadius, h) : 0
            sx: frame.launcherX + frame.launcherWidth; sy: frame.launcherBottom - f
            cx: sx + f; cy: sy
        }
        // Панель управления у полосы слева — DrawerShape, отражённый к низу.
        ShoulderRegion {
            readonly property real h: frame.controlPlace === "bottomLeft" ? frame.controlHeight * frame.controlProgress : 0
            f: h > 0.5 ? Math.min(Theme.frameRadius, h / 2) : 0
            sx: DesktopLayout.insetLeft + frame.controlWidth; sy: frame.height - DesktopLayout.insetBottom - f
            cx: sx + f; cy: sy
        }
        ShoulderRegion {
            readonly property real h: frame.controlPlace === "bottomLeft" ? frame.controlHeight * frame.controlProgress : 0
            f: h > 0.5 ? Math.min(Theme.frameRadius, h / 2) : 0
            sx: DesktopLayout.insetLeft; sy: frame.height - DesktopLayout.insetBottom - h - f
            cx: sx + f; cy: sy
        }
        // Панель управления сверху справа и уведомления — DrawerShape,
        // отражённый к правому краю.
        ShoulderRegion {
            readonly property real h: frame.controlPlace === "topRight" ? frame.controlHeight * frame.controlProgress : 0
            f: h > 0.5 ? Math.min(Theme.frameRadius, h / 2) : 0
            sx: frame.width - DesktopLayout.insetRight - frame.controlWidth - f; sy: DesktopLayout.insetTop
            cx: sx; cy: sy + f
        }
        ShoulderRegion {
            readonly property real h: frame.controlPlace === "topRight" ? frame.controlHeight * frame.controlProgress : 0
            f: h > 0.5 ? Math.min(Theme.frameRadius, h / 2) : 0
            sx: frame.width - DesktopLayout.insetRight - f; sy: DesktopLayout.insetTop + h
            cx: sx; cy: sy + f
        }
        ShoulderRegion {
            readonly property real h: frame.notificationsHeight
            f: h > 0.5 ? Math.min(Theme.frameRadius, h / 2) : 0
            sx: frame.width - DesktopLayout.insetRight - frame.notificationsWidth - f; sy: DesktopLayout.insetTop
            cx: sx; cy: sy + f
        }
        ShoulderRegion {
            readonly property real h: frame.notificationsHeight
            f: h > 0.5 ? Math.min(Theme.frameRadius, h / 2) : 0
            sx: frame.width - DesktopLayout.insetRight - f; sy: DesktopLayout.insetTop + h
            cx: sx; cy: sy + f
        }
        // Календарь и буфер обмена — EdgeDrawerShape, отражённый к верху.
        ShoulderRegion {
            readonly property real h: frame.controlPlace === "topCenter" ? frame.controlHeight * frame.controlProgress : 0
            f: h > 0.5 ? Math.min(Theme.frameRadius, h) : 0
            sx: frame.controlX - f; sy: DesktopLayout.insetTop
            cx: sx; cy: sy + f
        }
        ShoulderRegion {
            readonly property real h: frame.controlPlace === "topCenter" ? frame.controlHeight * frame.controlProgress : 0
            f: h > 0.5 ? Math.min(Theme.frameRadius, h) : 0
            sx: frame.controlX + frame.controlWidth; sy: DesktopLayout.insetTop
            cx: sx + f; cy: sy + f
        }
        ShoulderRegion {
            readonly property real h: frame.panelHeight * frame.panelProgress
            f: h > 0.5 ? Math.min(Theme.frameRadius, h) : 0
            sx: hole.x + hole.width / 2 - frame.panelWidth / 2 - f; sy: DesktopLayout.insetTop
            cx: sx; cy: sy + f
        }
        ShoulderRegion {
            readonly property real h: frame.panelHeight * frame.panelProgress
            f: h > 0.5 ? Math.min(Theme.frameRadius, h) : 0
            sx: hole.x + hole.width / 2 + frame.panelWidth / 2; sy: DesktopLayout.insetTop
            cx: sx + f; cy: sy + f
        }
        // Индикатор — EdgeDrawerShape снизу (с доком — отражённый к верху).
        ShoulderRegion {
            readonly property real h: 54 * frame.osdProgress
            f: h > 0.5 ? Math.min(Theme.frameRadius, h) : 0
            sx: hole.x + hole.width / 2 - frame.osdWidth / 2 - f
            sy: frame.osdOnTop ? DesktopLayout.insetTop : frame.height - DesktopLayout.insetBottom - f
            cx: sx; cy: frame.osdOnTop ? sy + f : sy
        }
        ShoulderRegion {
            readonly property real h: 54 * frame.osdProgress
            f: h > 0.5 ? Math.min(Theme.frameRadius, h) : 0
            sx: hole.x + hole.width / 2 + frame.osdWidth / 2
            sy: frame.osdOnTop ? DesktopLayout.insetTop : frame.height - DesktopLayout.insetBottom - f
            cx: sx + f; cy: frame.osdOnTop ? sy + f : sy
        }

        // Меню Win+X — карточка, растёт и сдвигается при появлении.
        Region {
            readonly property bool shown: quickMenu.visible && quickMenu.opacity > 0.3
            readonly property rect box: {
                quickMenu.scale; quickMenu.x; quickMenu.y; quickMenu.width; quickMenu.height;
                quickMenuShift.x; quickMenuShift.y;
                return frame.sceneBox(quickMenu);
            }
            intersection: Intersection.Combine
            x: shown ? Math.round(box.x) : 0
            y: shown ? Math.round(box.y) : 0
            width: shown ? Math.round(box.width) : 0
            height: shown ? Math.round(box.height) : 0
            radius: Math.round(12 * quickMenu.scale)
        }
    }

    mask: Region {
        item: content
        Region { item: frame.anyOpen ? null : hole; intersection: Intersection.Subtract }
        Region { item: frame.notificationsShown ? notifications : null; intersection: Intersection.Combine }
        Region { item: frame.dockProgress > 0 ? dockLoader : null; intersection: Intersection.Combine }
        Region { item: DesktopLayout.dock && !frame.dockShown ? reveal : null; intersection: Intersection.Combine }
    }

    Item {
        id: content
        anchors.fill: parent

        // Проём рамки: здесь видны окна программ.
        Item {
            id: hole
            x: DesktopLayout.insetLeft
            y: DesktopLayout.insetTop
            width: frame.width - DesktopLayout.insetLeft - DesktopLayout.insetRight
            height: frame.height - DesktopLayout.insetTop - DesktopLayout.insetBottom
        }

        // Клик мимо открытого запуска или панели закрывает их.
        MouseArea {
            anchors.fill: hole
            enabled: frame.anyOpen
            onClicked: ShellState.closeAll()
        }

        // Выехавшие панели ловят клики целиком, вместе с полями и
        // промежутками: иначе клик мимо кнопки внутри панели провалится
        // в «клик мимо панели» выше и закроет её.
        MouseArea {
            visible: frame.launcherOpen
            x: frame.launcherX
            y: frame.launcherY
            width: frame.launcherWidth
            height: frame.launcherHeight
        }
        MouseArea {
            visible: frame.controlOpen
            x: frame.controlX
            y: frame.controlY
            width: frame.controlWidth
            height: frame.controlHeight
        }
        MouseArea {
            visible: frame.panelOpen
            x: hole.x + hole.width / 2 - frame.panelWidth / 2
            y: DesktopLayout.insetTop
            width: frame.panelWidth
            height: frame.panelHeight
        }
        MouseArea {
            visible: frame.quickMenuOpen
            x: quickMenu.x
            y: quickMenu.y
            width: quickMenu.width
            height: quickMenu.height
        }
        MouseArea {
            visible: frame.centerOpen
            x: frame.width - DesktopLayout.insetRight - frame.notificationsWidth
            y: DesktopLayout.insetTop
            width: frame.notificationsWidth
            height: frame.notificationsHeight
        }

        // Всё, что сделано из «бумаги» рамки, — в одном слое: так у рамки
        // и выезжающих панелей общая тень и нет шва на стыке.
        Item {
            id: paper
            anchors.fill: parent
            // Стекло: бумага вместе с тенью полупрозрачна, под ней — размытое.
            opacity: frame.glass
            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Theme.shadow
                shadowOpacity: 0.28
                shadowBlur: 0.7
                blurMax: 24
            }

            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer

                ShapePath {
                    fillColor: Theme.paper
                    strokeColor: "transparent"
                    fillRule: ShapePath.OddEvenFill

                    PathRectangle { x: 0; y: 0; width: frame.width; height: frame.height }
                    PathRectangle {
                        x: hole.x; y: hole.y; width: hole.width; height: hole.height
                        radius: DesktopLayout.holeRadius
                    }
                }
            }

            // Край проёма — тонкая линия: видно, где кончается панель и
            // начинается окно. Лежит внутри проёма (на окно — 1 пиксель);
            // выезжающие панели рисуются поверх и пристают без шва.
            Shape {
                visible: DesktopLayout.left
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    fillColor: "transparent"
                    strokeColor: Theme.lineStrong
                    strokeWidth: 1
                    PathRectangle {
                        x: hole.x + 0.5; y: hole.y + 0.5
                        width: hole.width - 1; height: hole.height - 1
                        radius: Math.max(0, DesktopLayout.holeRadius - 0.5)
                    }
                }
            }
            Rectangle {
                visible: DesktopLayout.topBar
                x: hole.x; y: hole.y
                width: hole.width; height: 1
                color: Theme.lineStrong
            }
            Rectangle {
                visible: DesktopLayout.taskbar
                x: hole.x; y: hole.y + hole.height - 1
                width: hole.width; height: 1
                color: Theme.lineStrong
            }

            // Запуск: из угла сверху слева (полоса слева)…
            DrawerShape {
                visible: DesktopLayout.left && drawerHeight > 0.5
                x0: DesktopLayout.insetLeft
                y0: DesktopLayout.insetTop
                drawerWidth: frame.launcherWidth
                drawerHeight: frame.launcherHeight * frame.launcherProgress
            }
            // …из панели задач снизу…
            EdgeDrawerShape {
                visible: DesktopLayout.taskbar && drawerHeight > 0.5
                centerX: frame.launcherX + frame.launcherWidth / 2
                edgeY: frame.launcherBottom
                drawerWidth: frame.launcherWidth
                drawerHeight: frame.launcherHeight * frame.launcherProgress
            }
            // …карточкой над доком.
            Rectangle {
                visible: DesktopLayout.dock && frame.launcherProgress > 0
                x: frame.launcherX
                y: frame.launcherBottom - height
                width: frame.launcherWidth
                height: frame.launcherHeight * frame.launcherProgress
                radius: Math.min(Theme.frameRadius, height / 2)
                color: Theme.paper
            }

            // Док.
            Rectangle {
                visible: frame.dockProgress > 0
                x: frame.dockX
                y: frame.dockY
                width: frame.dockWidth
                height: DesktopLayout.dockHeight
                radius: Theme.frameRadius
                color: Theme.paper
            }

            // Уведомления: та же форма, отражённая к правому краю.
            Item {
                anchors.fill: parent
                transform: Scale { xScale: -1; origin.x: frame.width / 2 }

                DrawerShape {
                    x0: DesktopLayout.insetRight
                    y0: DesktopLayout.insetTop
                    drawerWidth: frame.notificationsWidth
                    drawerHeight: frame.notificationsHeight
                }
            }

            // Панель управления: у полосы слева — отражённая к низу экрана…
            Item {
                anchors.fill: parent
                visible: frame.controlPlace === "bottomLeft"
                transform: Scale { yScale: -1; origin.y: frame.height / 2 }

                DrawerShape {
                    x0: DesktopLayout.insetLeft
                    y0: DesktopLayout.insetBottom
                    drawerWidth: frame.controlWidth
                    drawerHeight: frame.controlHeight * frame.controlProgress
                }
            }
            // …под кнопками верхней панели — как уведомления…
            Item {
                anchors.fill: parent
                visible: frame.controlPlace === "topRight"
                transform: Scale { xScale: -1; origin.x: frame.width / 2 }

                DrawerShape {
                    x0: DesktopLayout.insetRight
                    y0: DesktopLayout.insetTop
                    drawerWidth: frame.controlWidth
                    drawerHeight: frame.controlHeight * frame.controlProgress
                }
            }
            // …календарь — из верхней панели посередине.
            Item {
                anchors.fill: parent
                visible: frame.controlPlace === "topCenter"
                transform: Scale { yScale: -1; origin.y: frame.height / 2 }

                EdgeDrawerShape {
                    centerX: frame.controlX + frame.controlWidth / 2
                    edgeY: frame.height - DesktopLayout.insetTop
                    drawerWidth: frame.controlWidth
                    drawerHeight: frame.controlHeight * frame.controlProgress
                }
            }

            // Шторка модуля (буфер обмена): та же форма, что у индикатора, отражённая к верху.
            Item {
                anchors.fill: parent
                transform: Scale { yScale: -1; origin.y: frame.height / 2 }

                EdgeDrawerShape {
                    centerX: hole.x + hole.width / 2
                    edgeY: frame.height - DesktopLayout.insetTop
                    drawerWidth: frame.panelWidth
                    drawerHeight: frame.panelHeight * frame.panelProgress
                }
            }

            // Индикатор громкости и яркости: снизу посередине, с доком — сверху.
            Item {
                anchors.fill: parent
                transform: Scale { yScale: frame.osdOnTop ? -1 : 1; origin.y: frame.height / 2 }

                EdgeDrawerShape {
                    centerX: hole.x + hole.width / 2
                    edgeY: frame.height - (frame.osdOnTop ? DesktopLayout.insetTop : DesktopLayout.insetBottom)
                    drawerWidth: frame.osdWidth
                    drawerHeight: 54 * frame.osdProgress
                }
            }
        }

        Launcher {
            id: launcher
            open: frame.launcherOpen
            x: frame.launcherX + 14
            y: frame.launcherY + 12
            width: frame.launcherWidth - 28
            height: frame.launcherHeight - 26
            maxHeight: frame.launcherMaxHeight - 26
            clip: true
            opacity: Math.max(0, frame.launcherProgress * 2 - 1)
            visible: frame.launcherProgress > 0
            transform: Translate { y: (1 - frame.launcherProgress) * (DesktopLayout.left ? -24 : 24) }
            onCloseRequested: restoreFocus => ShellState.closeAll(restoreFocus)
        }

        ControlPanel {
            id: control
            open: frame.controlOpen
            section: ShellState.controlSection
            x: frame.controlX + 14
            y: frame.controlY + 14
            width: frame.controlWidth - 28
            height: frame.controlHeight - 28
            maxHeight: hole.height - 60
            clip: true
            opacity: Math.max(0, frame.controlProgress * 2 - 1)
            visible: frame.controlProgress > 0
            transform: Translate { y: (1 - frame.controlProgress) * (frame.controlPlace === "bottomLeft" ? 24 : -24) }
            onCloseRequested: restoreFocus => ShellState.closeAll(restoreFocus)
        }

        // Содержимое шторки — часть "panel" модуля (ModulePart): open,
        // maxHeight, wantedHeight, сигнал closeRequested(bool).
        ModulePart {
            id: panel
            module: frame.panelModule
            part: "panel"
            props: ({ open: frame.panelOpen, maxHeight: Math.min(640, hole.height - 120) })
            x: hole.x + hole.width / 2 - frame.panelWidth / 2 + 14
            y: DesktopLayout.insetTop + 14
            width: frame.panelWidth - 28
            height: frame.panelHeight - 28
            clip: true
            opacity: Math.max(0, frame.panelProgress * 2 - 1)
            visible: frame.panelProgress > 0
            transform: Translate { y: (1 - frame.panelProgress) * -24 }
            Connections {
                target: panel.item
                ignoreUnknownSignals: true
                function onCloseRequested(restoreFocus) { ShellState.closeAll(restoreFocus); }
            }
        }

        // Центр — часть "center" модуля (ModulePart): open, maxHeight,
        // wantedHeight, сигнал closeRequested(bool).
        ModulePart {
            id: center
            module: ShellState.centerModule
            part: "center"
            props: ({ open: frame.centerOpen, maxHeight: hole.height - 60 })
            x: frame.width - DesktopLayout.insetRight - frame.notificationsWidth + 14
            y: DesktopLayout.insetTop + 14
            width: frame.notificationsWidth - 28
            height: frame.notificationsHeight - 28
            clip: true
            opacity: frame.centerOpen ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
            Connections {
                target: center.item
                ignoreUnknownSignals: true
                function onCloseRequested(restoreFocus) { ShellState.closeAll(restoreFocus); }
            }
        }

        // Карточки операций (старые сверху), под ними уведомления (новые
        // сверху) — часть "popups" модуля, отдаёт count.
        Column {
            id: notifications
            x: frame.width - DesktopLayout.insetRight - width - 10
            y: DesktopLayout.insetTop + 10
            width: frame.notificationsWidth - 20
            spacing: 8
            opacity: frame.notificationsShown ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: Theme.animFast } }

            add: Transition {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.animNormal }
            }
            move: Transition {
                NumberAnimation { property: "y"; duration: Theme.animNormal; easing.type: Easing.OutCubic }
            }

            Repeater {
                model: ScriptModel { values: JobsState.popups }
                JobCard {
                    required property var modelData
                    job: modelData
                    width: notifications.width
                }
            }

            ModulePart {
                id: popups
                module: Modules.withPart("popups")[0] ?? ""
                part: "popups"
                props: ({ urgentOnly: false })
                width: notifications.width
                visible: item !== null && item.count > 0
            }
        }

        Osd {
            id: osd
            width: frame.osdWidth
            height: 54
            x: hole.x + hole.width / 2 - width / 2
            y: frame.osdOnTop ? DesktopLayout.insetTop - 54 + 54 * frame.osdProgress
                              : frame.height - DesktopLayout.insetBottom - 54 * frame.osdProgress
            opacity: Math.max(0, frame.osdProgress * 2 - 1)
            visible: frame.osdProgress > 0
        }

        // Меню Win+X — карточкой у знака Sedmio, поверх рамки.
        QuickMenu {
            id: quickMenu
            open: frame.quickMenuOpen
            screenName: frame.screenName
            x: frame.quickMenuX
            y: frame.quickMenuY
            width: implicitWidth
            height: implicitHeight
            opacity: frame.quickMenuOpen ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
            // Появляется от знака Sedmio с пружинкой, уходит быстро.
            scale: frame.quickMenuOpen ? 1 : 0.94
            transformOrigin: DesktopLayout.left ? Item.TopLeft : Item.BottomLeft
            Behavior on scale {
                NumberAnimation {
                    duration: frame.quickMenuOpen ? Motion.springDuration : Theme.animFast
                    easing.type: frame.quickMenuOpen ? Easing.BezierSpline : Easing.OutCubic
                    easing.bezierCurve: Motion.spring
                }
            }
            transform: Translate {
                id: quickMenuShift
                x: DesktopLayout.left && !frame.quickMenuOpen ? -8 : 0
                y: !DesktopLayout.left && !frame.quickMenuOpen ? 8 : 0
                Behavior on x {
                    NumberAnimation {
                        duration: frame.quickMenuOpen ? Motion.springDuration : Theme.animFast
                        easing.type: frame.quickMenuOpen ? Easing.BezierSpline : Easing.OutCubic
                        easing.bezierCurve: Motion.spring
                    }
                }
                Behavior on y {
                    NumberAnimation {
                        duration: frame.quickMenuOpen ? Motion.springDuration : Theme.animFast
                        easing.type: frame.quickMenuOpen ? Easing.BezierSpline : Easing.OutCubic
                        easing.bezierCurve: Motion.spring
                    }
                }
            }
            onCloseRequested: restoreFocus => ShellState.closeAll(restoreFocus)
        }

        // Панели по макету.
        Loader {
            active: DesktopLayout.left
            x: 0
            y: 0
            width: DesktopLayout.leftWidth
            height: frame.height
            sourceComponent: Bar {
                window: frame
                screenName: frame.screenName
                tooltip: frameTooltip
            }
        }
        Loader {
            active: DesktopLayout.topBar
            x: 0
            y: 0
            width: frame.width
            height: DesktopLayout.topBarHeight
            sourceComponent: TopBar {
                window: frame
                screenName: frame.screenName
                tooltip: frameTooltip
            }
        }
        Loader {
            active: DesktopLayout.taskbar
            x: 0
            y: frame.height - DesktopLayout.taskbarHeight
            width: frame.width
            height: DesktopLayout.taskbarHeight
            sourceComponent: Taskbar {
                window: frame
                screenName: frame.screenName
                tooltip: frameTooltip
            }
        }
        Loader {
            id: dockLoader
            active: DesktopLayout.dock
            x: frame.dockX
            y: frame.dockY
            width: frame.dockWidth
            height: DesktopLayout.dockHeight
            visible: frame.dockProgress > 0
            sourceComponent: Dock {
                window: frame
                screenName: frame.screenName
                tooltip: frameTooltip
                maxWidth: frame.width - 2 * DesktopLayout.dockMargin
            }
            HoverHandler {
                id: dockHover
                onHoveredChanged: frame.dockHoverChanged()
            }
        }
        // Полоска у нижнего края: мышь сюда — спрятанный док выезжает.
        Item {
            id: reveal
            x: 0
            y: frame.height - 2
            width: frame.width
            height: 2
            HoverHandler {
                id: revealHover
                enabled: DesktopLayout.dock
                onHoveredChanged: frame.dockHoverChanged()
            }
        }

        Tooltip { id: frameTooltip }
    }
}
