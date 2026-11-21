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

    function dragTo(pos) {
        const from = indexOfKey(dragKey);
        const over = horizontal ? indexAt(pos.x, height / 2) : indexAt(width / 2, pos.y);
        if (from < 0 || over < 0) return;
        const pinned = from < pinnedCount;
        const to = pinned ? Math.min(over, pinnedCount - 1) : Math.max(over, pinnedCount);
        if (to !== from && to >= 0 && to < keys.count) keys.move(from, to, 1);
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
        z: list.dragKey === key ? 1 : 0

        DragHandler {
            target: null
            xAxis.enabled: list.horizontal
            yAxis.enabled: !list.horizontal
            onActiveChanged: {
                if (active) {
                    if (list.tooltip) list.tooltip.hide();
                    list.dragKey = button.key;
                } else if (list.dragKey === button.key) {
                    list.dropDragged();
                }
            }
            onCentroidChanged: {
                if (active) list.dragTo(button.mapToItem(list.contentItem, centroid.position.x, centroid.position.y));
            }
        }
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
