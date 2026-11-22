import QtQuick
import Sedmio.Style

// Закреплённые программы и открытые окна, по кнопке на программу: окна
// одной программы — в одной кнопке. Диалоги («Свойства», «Сохранить как») не показываем — они всегда
// над своим окном и поднимаются вместе с ним. Список даёт ToplevelManager —
// в нашей сборке Quickshell он работает и под KWin
// (org_kde_plasma_window_management).
ListView {
    id: list
    required property var window
    required property Item tooltip
    // В строку (док, панель задач) или столбиком (полоса слева).
    property bool horizontal: false
    // С подписями (панель задач): у запущенных — заголовок окна.
    property bool labeled: false
    property real buttonSize: Theme.buttonSize

    // Программы и их окна — в ShellState (по ним же работают Meta+1…9).
    readonly property var groups: ShellState.windowGroups

    function groupOf(key) {
        return groups.find(g => g.key === key) || null;
    }

    // Модель — только ключи программ, и меняется она точечно: так кнопки
    // не пересоздаются, а появляются и уходят с анимацией.
    ListModel { id: keys }
    function sync() {
        const wanted = groups.map(g => g.key);
        for (let i = keys.count - 1; i >= 0; --i) {
            if (!wanted.includes(keys.get(i).key)) keys.remove(i);
        }
        for (let i = 0; i < wanted.length; ++i) {
            if (i < keys.count && keys.get(i).key === wanted[i]) continue;
            let from = -1;
            for (let j = i + 1; j < keys.count; ++j) {
                if (keys.get(j).key === wanted[i]) { from = j; break; }
            }
            if (from >= 0) keys.move(from, i, 1);
            else keys.insert(i, { key: wanted[i] });
        }
    }
    onGroupsChanged: if (dragKey === "") sync()

    // Перетаскивание кнопок, как на панели задач Windows: кнопка встаёт на
    // место той, над которой её держат, — закреплённая среди закреплённых
    // (порядок сохраняется в PinnedApps), остальные среди остальных
    // (ShellState.runningOrder — пока работает оболочка).
    property string dragKey: ""
    readonly property int pinnedCount: groups.filter(g => g.pinned).length

    function indexOfKey(key) {
        for (let i = 0; i < keys.count; ++i) if (keys.get(i).key === key) return i;
        return -1;
    }

    function sizeAt(i) {
        const it = itemAtIndex(i);
        return it ? (horizontal ? it.width : it.height) : 0;
    }

    // p — указатель в координатах содержимого списка. Кнопка меняется
    // местами с соседней, когда её передний край заходит за середину
    // соседней. Места считаем по ширинам, а не по x кнопок: соседи в это
    // время ещё едут (displaced), и по их x кнопки менялись бы туда-обратно.
    function dragTo(p) {
        const from = indexOfKey(dragKey);
        const item = from >= 0 ? itemAtIndex(from) : null;
        if (!item) return;
        const [lo, hi] = dragRange(from);
        const size = sizeAt(from);
        const others = [];
        for (let i = lo; i <= hi; ++i) if (i !== from) others.push(sizeAt(i));
        const slot = t => {   // начало кнопки, если она t-я в своей группе
            let s = rangeStart(lo);
            for (let k = 0; k < t; ++k) s += others[k] + spacing;
            return s;
        };
        const pos = (horizontal ? p.x : p.y) - item.grab;
        let t = from - lo;
        while (t < others.length && pos + size > slot(t) + size + spacing + others[t] / 2) ++t;
        if (t === from - lo) {
            while (t > 0 && pos < slot(t - 1) + others[t - 1] / 2) --t;
        }
        if (lo + t !== from) keys.move(from, lo + t, 1);
    }

    // Куда можно поставить кнопку: закреплённую — среди закреплённых,
    // остальные — после них.
    function dragRange(index) {
        return index < pinnedCount ? [0, pinnedCount - 1] : [pinnedCount, keys.count - 1];
    }

    // Докуда кнопка index (размер size) может уехать за указателем — не за
    // свою группу. Края берём по соседям снаружи группы: они во время
    // перетаскивания стоят на месте.
    function rangeStart(lo) {
        const before = lo > 0 ? itemAtIndex(lo - 1) : null;
        return before ? (horizontal ? before.x + before.width : before.y + before.height) + spacing
                      : (horizontal ? originX : originY);
    }
    function dragBounds(index, size) {
        const [lo, hi] = dragRange(index);
        const after = hi < keys.count - 1 ? itemAtIndex(hi + 1) : null;
        const end = after ? (horizontal ? after.x : after.y) - spacing
                          : (horizontal ? originX + contentWidth : originY + contentHeight);
        return [rangeStart(lo), end - size];
    }

    function dropDragged() {
        const order = [];
        for (let i = 0; i < keys.count; ++i) order.push(keys.get(i).key);
        const pinned = groupOf(dragKey)?.pinned ?? false;
        dragKey = "";
        if (pinned) PinnedApps.setOrder(order);
        else ShellState.runningOrder = order.slice(pinnedCount);
        sync();
    }
    Component.onCompleted: sync()

    clip: true
    spacing: 4
    orientation: horizontal ? ListView.Horizontal : ListView.Vertical
    interactive: dragKey === "" && (horizontal ? contentWidth > width : contentHeight > height)
    boundsBehavior: Flickable.StopAtBounds
    model: keys

    delegate: WindowButton {
        id: button
        required property string key
        group: list.groupOf(key)
        window: list.window
        tooltip: list.tooltip
        horizontal: list.horizontal
        labeled: list.labeled
        buttonSize: list.buttonSize
        width: list.horizontal ? implicitWidth : ListView.view.width
        height: list.horizontal ? ListView.view.height : implicitHeight
        z: list.dragKey === key || settle.running ? 1 : 0

        // Перетаскиваемая кнопка идёт за указателем: её место в списке
        // меняется скачком (keys.move), а сдвиг shift держит её под пальцем;
        // отпустили — доезжает на своё место.
        property real grab        // где взяли кнопку, от её начала
        property real shift: 0
        transform: Translate {
            x: list.horizontal ? button.shift : 0
            y: list.horizontal ? 0 : button.shift
        }
        function follow(pointer) {
            if (list.dragKey !== key) return;
            const p = list.contentItem.mapFromItem(null, pointer.x, pointer.y);
            list.dragTo(p);
            const [min, max] = list.dragBounds(list.indexOfKey(key), list.horizontal ? width : height);
            const pos = (list.horizontal ? p.x : p.y) - grab;
            shift = Math.max(min, Math.min(max, pos)) - (list.horizontal ? x : y);
        }
        NumberAnimation {
            id: settle
            target: button
            property: "shift"
            to: 0
            duration: Theme.animNormal
            easing.type: Easing.OutCubic
        }

        DragHandler {
            id: drag
            target: null
            xAxis.enabled: list.horizontal
            yAxis.enabled: !list.horizontal
            onActiveChanged: {
                if (active) {
                    settle.stop();
                    if (list.tooltip) list.tooltip.hide();
                    const p = list.contentItem.mapFromItem(null, centroid.scenePressPosition.x, centroid.scenePressPosition.y);
                    button.grab = list.horizontal ? p.x - button.x : p.y - button.y;
                    list.dragKey = button.key;
                    button.follow(centroid.scenePosition);
                } else if (list.dragKey === button.key) {
                    list.dropDragged();
                    settle.start();
                }
            }
            onCentroidChanged: if (active) button.follow(centroid.scenePosition)
        }
        // Место сменилось (keys.move) — сдвиг пересчитать, чтобы кнопка не прыгнула.
        onXChanged: if (drag.active) follow(drag.centroid.scenePosition)
        onYChanged: if (drag.active) follow(drag.centroid.scenePosition)
    }

    // Без анимации появления в панели задач: пока она идёт, ListView кнопку
    // не двигает и потом сам не перекладывает, а соседняя кнопка в это время
    // как раз расширяется (появилась подпись) — кнопки налезали друг на друга.
    add: labeled ? null : appear
    Transition {
        id: appear
        NumberAnimation { property: "scale"; from: 0.5; to: 1; duration: Theme.animNormal; easing.type: Easing.OutBack }
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.animFast }
    }
    remove: Transition {
        NumberAnimation { property: "scale"; to: 0.5; duration: Theme.animFast }
        NumberAnimation { property: "opacity"; to: 0; duration: Theme.animFast }
    }
    displaced: Transition {
        NumberAnimation { properties: "x,y"; duration: Theme.animNormal; easing.type: Easing.OutCubic }
    }
}
