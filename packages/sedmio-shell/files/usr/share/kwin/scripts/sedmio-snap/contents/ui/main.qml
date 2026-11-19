import QtQuick
import org.kde.kwin as KWin
import Sedmio.Style

// Привязка окон как в Windows 11 (включена в /etc/xdg/kwinrc).
//
// Раскладки: тянешь окно за заголовок — у верхнего края экрана посередине
// полоска; подвёл к ней курсор — она раскрывается схемами (половины,
// 2/3 + 1/3, три колонки, половина и две четверти, четверти, на широком
// экране ещё 1/4 + 1/2 + 1/4). Отпустил окно над частью схемы — окно
// встаёт туда. Край экрана (развернуть) и боковые края (половина, четверть)
// по-прежнему у KWin.
//
// Подбор окон (Snap Assist): окно встало в схему или KWin прилепил его к
// боковому краю — на свободном месте миниатюры остальных окон. Щелчок —
// окно встаёт туда, Esc или щелчок мимо — не надо.
//
// Место окну задаём сами (frameGeometry), плитки KWin (Meta+T) не трогаем.
// Прежний размер помним: потянул окно с места — размер вернулся, как в
// Windows.
Item {
    id: root

    // ---- Схемы: части экрана долями [x, y, ширина, высота]

    readonly property var baseLayouts: [
        [[0, 0, 1 / 2, 1], [1 / 2, 0, 1 / 2, 1]],
        [[0, 0, 2 / 3, 1], [2 / 3, 0, 1 / 3, 1]],
        [[0, 0, 1 / 3, 1], [1 / 3, 0, 1 / 3, 1], [2 / 3, 0, 1 / 3, 1]],
        [[0, 0, 1 / 2, 1], [1 / 2, 0, 1 / 2, 1 / 2], [1 / 2, 1 / 2, 1 / 2, 1 / 2]],
        [[0, 0, 1 / 2, 1 / 2], [1 / 2, 0, 1 / 2, 1 / 2], [0, 1 / 2, 1 / 2, 1 / 2], [1 / 2, 1 / 2, 1 / 2, 1 / 2]]
    ]
    readonly property var wideLayout: [[0, 0, 1 / 4, 1], [1 / 4, 0, 1 / 2, 1], [3 / 4, 0, 1 / 4, 1]]

    function layoutsFor(area) {
        return area.width >= 1900 ? baseLayouts.concat([wideLayout]) : baseLayouts;
    }

    // Часть схемы в точках экрана; соседние части сходятся без щелей.
    function zoneRect(area, z) {
        const x1 = Math.round(area.x + z[0] * area.width);
        const y1 = Math.round(area.y + z[1] * area.height);
        const x2 = Math.round(area.x + (z[0] + z[2]) * area.width);
        const y2 = Math.round(area.y + (z[1] + z[3]) * area.height);
        return Qt.rect(x1, y1, x2 - x1, y2 - y1);
    }

    function areaAt(pos) {
        const output = KWin.Workspace.screenAt(pos);
        return KWin.Workspace.clientArea(KWin.Workspace.MaximizeArea, output, KWin.Workspace.currentDesktop);
    }

    function near(a, b) {
        return Math.abs(a.x - b.x) <= 2 && Math.abs(a.y - b.y) <= 2
            && Math.abs(a.width - b.width) <= 2 && Math.abs(a.height - b.height) <= 2;
    }

    function onCurrentDesktop(w) {
        return w.onAllDesktops || w.desktops.indexOf(KWin.Workspace.currentDesktop) !== -1;
    }

    // ---- Окна, поставленные в схему, и их прежний размер

    property var snapped: ({})   // internalId → { width, height, rect }

    function key(w) {
        return w.internalId.toString();
    }

    function forget(w) {
        delete snapped[key(w)];
    }

    function place(w, rect) {
        const prev = snapped[key(w)];
        let size = prev ? Qt.size(prev.width, prev.height) : Qt.size(w.frameGeometry.width, w.frameGeometry.height);
        if (w.minimized)
            w.minimized = false;
        if (w.maximizeMode !== 0) {
            const r = w.maximizeGeometryRestore;
            if (!prev && r && r.width > 0)
                size = Qt.size(r.width, r.height);
            w.setMaximize(false, false);
        }
        if (w.tile)
            w.tile.unmanage(w);
        w.frameGeometry = rect;
        snapped[key(w)] = { width: size.width, height: size.height, rect: rect };
    }

    // ---- Перетаскивание окна

    property var dragged: null
    property rect dragArea
    property var dragLayouts: []
    property bool barOpen: false
    property int hoverLayout: -1
    property int hoverZone: -1

    // Полоска схем: размеры — общие для расчёта попадания и для вида.
    readonly property int barPad: 10
    readonly property int barGap: 10
    readonly property int thumbWidth: 88
    readonly property int thumbHeight: Math.round(thumbWidth * dragArea.height / Math.max(1, dragArea.width))
    readonly property rect barRect: {
        const n = dragLayouts.length;
        const w = n * thumbWidth + (n - 1) * barGap + 2 * barPad;
        const h = thumbHeight + 2 * barPad;
        return Qt.rect(Math.round(dragArea.x + (dragArea.width - w) / 2), dragArea.y + 10, w, h);
    }

    function thumbRect(i) {
        return Qt.rect(barRect.x + barPad + i * (thumbWidth + barGap), barRect.y + barPad, thumbWidth, thumbHeight);
    }

    function moveStarted(w) {
        closeAssist();
        const s = snapped[key(w)];
        if (w.resize) {
            // Растянул окно в схеме — оно всё ещё в ней, прежний размер тот же.
            return;
        }
        if (!w.move)
            return;
        if (s) {
            forget(w);
            const g = w.frameGeometry;
            if (near(g, s.rect)) {
                // Как в Windows: окно возвращает прежний размер и остаётся
                // под курсором в том же месте по ширине.
                const c = KWin.Workspace.cursorPos;
                const area = areaAt(c);
                const width = Math.min(s.width, area.width), height = Math.min(s.height, area.height);
                const fx = Math.max(0, Math.min(1, (c.x - g.x) / Math.max(1, g.width)));
                w.frameGeometry = Qt.rect(Math.round(c.x - fx * width), g.y, width, height);
            }
        }
        if (!w.resizeable || w.fullScreen)
            return;
        dragged = w;
        barOpen = false;
        hoverLayout = -1;
        hoverZone = -1;
        moveStepped(w);
    }

    function moveStepped(w) {
        if (dragged !== w)
            return;
        const c = KWin.Workspace.cursorPos;
        const area = areaAt(c);
        if (!near(area, dragArea)) {
            dragArea = area;
            dragLayouts = layoutsFor(area);
        }
        const bar = barRect;
        const inBar = c.x >= bar.x - 16 && c.x <= bar.x + bar.width + 16
            && c.y >= area.y + 4 && c.y <= bar.y + bar.height + 16;
        // Закрытая полоска раскрывается, когда курсор зашёл на её место.
        const reached = c.x >= bar.x && c.x <= bar.x + bar.width && c.y >= area.y + 4 && c.y <= bar.y + bar.height;
        barOpen = barOpen ? inBar : reached;
        let layout = -1, zone = -1;
        if (barOpen) {
            for (let i = 0; i < dragLayouts.length && layout < 0; ++i) {
                const t = thumbRect(i);
                if (c.x < t.x || c.x >= t.x + t.width || c.y < t.y || c.y >= t.y + t.height)
                    continue;
                const fx = (c.x - t.x) / t.width, fy = (c.y - t.y) / t.height;
                const zones = dragLayouts[i];
                for (let j = 0; j < zones.length; ++j) {
                    const z = zones[j];
                    if (fx >= z[0] && fx < z[0] + z[2] && fy >= z[1] && fy < z[1] + z[3]) {
                        layout = i;
                        zone = j;
                        break;
                    }
                }
            }
        }
        hoverLayout = layout;
        hoverZone = zone;
    }

    function moveFinished(w) {
        if (dragged !== w)
            return;
        const layout = hoverLayout >= 0 ? dragLayouts[hoverLayout] : null;
        const zone = hoverZone;
        const area = dragArea;
        dragged = null;
        barOpen = false;
        hoverLayout = -1;
        hoverZone = -1;
        if (!layout || zone < 0)
            return;
        place(w, zoneRect(area, layout[zone]));
        const rest = [];
        for (let j = 0; j < layout.length; ++j) {
            if (j !== zone)
                rest.push(zoneRect(area, layout[j]));
        }
        startAssist(w, rest);
    }

    // KWin прилепил окно к боковому краю (перетаскивание, Win+←/→): на
    // оставшемся месте — подбор окна, если оно прямоугольное.
    function tileChanged(w) {
        const tile = w.tile;
        if (!tile)
            return;
        forget(w);
        if (dragged)
            return;
        const t = tile.absoluteGeometry;
        const area = KWin.Workspace.clientArea(KWin.Workspace.MaximizeArea, w.output, KWin.Workspace.currentDesktop);
        const left = t.x - area.x, right = area.x + area.width - (t.x + t.width);
        const top = t.y - area.y, bottom = area.y + area.height - (t.y + t.height);
        let rest = null;
        if (top <= 2 && bottom <= 2) {
            if (left <= 2 && right > 2)
                rest = Qt.rect(t.x + t.width, area.y, right, area.height);
            else if (right <= 2 && left > 2)
                rest = Qt.rect(area.x, area.y, left, area.height);
        } else if (left <= 2 && right <= 2) {
            if (top <= 2 && bottom > 2)
                rest = Qt.rect(area.x, t.y + t.height, area.width, bottom);
            else if (bottom <= 2 && top > 2)
                rest = Qt.rect(area.x, area.y, area.width, top);
        }
        if (rest)
            Qt.callLater(startAssist, w, [rest]);
    }

    // ---- Подбор окон на свободные места

    property var assistGroup: []     // окна, уже расставленные
    property var assistQueue: []     // свободные места по очереди
    property var assistWindows: []   // кого предложить
    property rect assistZone
    property bool assistClosing: false

    function candidates(group) {
        return KWin.Workspace.stackingOrder.slice().reverse().filter(w =>
            w.normalWindow && !w.skipTaskbar && w.resizeable && !w.fullScreen
            && onCurrentDesktop(w) && group.indexOf(w) === -1);
    }

    // Место уже занято окном, что стоит ровно там, — его не предлагаем.
    function occupied(rect, group) {
        return KWin.Workspace.stackingOrder.some(w =>
            w.normalWindow && !w.minimized && onCurrentDesktop(w) && group.indexOf(w) === -1
            && near(w.frameGeometry, rect));
    }

    function startAssist(w, zones) {
        closeAssist();
        assistGroup = [w];
        assistQueue = zones.filter(r => !occupied(r, [w]));
        nextAssist();
    }

    function nextAssist() {
        const list = assistQueue.length > 0 ? candidates(assistGroup) : [];
        if (list.length === 0) {
            closeAssist();
            return;
        }
        assistWindows = list;
        assistZone = assistQueue[0];
        assistPopup.show();
        // KWin ставит новое окно по-своему — место задаём после показа.
        assistPopup.x = assistZone.x;
        assistPopup.y = assistZone.y;
        assistPopup.width = Math.max(1, assistZone.width);
        assistPopup.height = Math.max(1, assistZone.height);
        assistPopup.requestActivate();
        assistView.reset();
    }

    function pick(w) {
        const zone = assistQueue.shift();
        hideAssistPopup();
        if (!w || !zone) {
            closeAssist();
            return;
        }
        place(w, zone);
        assistGroup.push(w);
        KWin.Workspace.activeWindow = w;
        // Окно должно успеть стать активным, иначе новый список сразу
        // закроется щелчком мимо.
        Qt.callLater(nextAssist);
    }

    function closeAssist() {
        assistGroup = [];
        assistQueue = [];
        assistWindows = [];
        hideAssistPopup();
    }

    function hideAssistPopup() {
        if (!assistPopup.visible)
            return;
        assistClosing = true;
        assistPopup.hide();
        assistClosing = false;
    }

    // Сигналы окон — через Connections: их KWin убирает вместе со
    // скриптом, а подключённые из JS остались бы висеть после выгрузки.
    Instantiator {
        model: KWin.WindowModel {}
        delegate: Connections {
            required property var window
            target: window
            enabled: window.normalWindow
            function onInteractiveMoveResizeStarted() { root.moveStarted(window); }
            function onInteractiveMoveResizeStepped() { Qt.callLater(root.moveStepped, window); }
            function onInteractiveMoveResizeFinished() { root.moveFinished(window); }
            function onTileChanged() { root.tileChanged(window); }
            function onMaximizedChanged() { if (window.maximizeMode !== 0) root.forget(window); }
            function onFullScreenChanged() { if (window.fullScreen) root.forget(window); }
        }
    }

    Connections {
        target: KWin.Workspace
        function onWindowRemoved(w) {
            root.forget(w);
            if (root.assistGroup.indexOf(w) !== -1 || root.assistWindows.indexOf(w) !== -1)
                root.closeAssist();
        }
        function onCurrentDesktopChanged() { root.closeAssist(); }
    }

    // ---- Полоска схем у верхнего края и подсветка места под окно

    // Окно поверх всех, без фокуса. Показываем и двигаем сами: окно,
    // показанное привязкой visible, KWin не выводит.
    component Overlay: Window {
        id: overlay
        property bool shown: false
        property rect geometry
        flags: Qt.ToolTip | Qt.FramelessWindowHint | Qt.X11BypassWindowManagerHint
        color: "transparent"
        visible: false

        function apply() {
            if (!shown) {
                hide();
                return;
            }
            if (!visible)
                show();
            x = geometry.x;
            y = geometry.y;
            width = Math.max(1, geometry.width);
            height = Math.max(1, geometry.height);
        }
        onShownChanged: apply()
        onGeometryChanged: if (shown) apply()
    }

    Overlay {
        shown: root.dragged !== null && root.dragLayouts.length > 0
        geometry: root.barRect

        SnapBar {
            anchors.fill: parent
            snap: root
        }
    }

    Overlay {
        readonly property var zone: root.hoverLayout >= 0 && root.hoverZone >= 0
            ? (root.dragLayouts[root.hoverLayout] ?? [])[root.hoverZone] : undefined
        shown: root.dragged !== null && zone !== undefined
        geometry: zone !== undefined ? root.zoneRect(root.dragArea, zone) : Qt.rect(0, 0, 1, 1)

        Rectangle {
            anchors { fill: parent; margins: 6 }
            radius: Theme.frameRadius
            color: Qt.alpha(Theme.green, 0.18)
            border.width: 2
            border.color: Theme.green
        }
    }

    // ---- Подбор окна на свободное место

    Window {
        id: assistPopup
        // Popup: KWin отдаёт ему клавиатуру, щелчок мимо закрывает.
        flags: Qt.Popup | Qt.FramelessWindowHint
        color: "transparent"
        visible: false
        onVisibleChanged: if (!visible && !root.assistClosing) root.closeAssist()

        SnapAssist {
            id: assistView
            anchors.fill: parent
            windows: root.assistWindows
            onPicked: w => root.pick(w)
            onCancelled: root.closeAssist()
        }
    }
}
