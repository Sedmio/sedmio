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

    // Перетаскивание закреплённых кнопок, как на панели задач Windows:
    // кнопка встаёт на место той, над которой её держат, — среди
    // закреплённых; отпустили — порядок сохраняется (PinnedApps).
    property string dragKey: ""
    readonly property int pinnedCount: groups.filter(g => g.pinned).length

    function indexOfKey(key) {
        for (let i = 0; i < keys.count; ++i) if (keys.get(i).key === key) return i;
        return -1;
    }

    function dragTo(y) {
        const from = indexOfKey(dragKey);
        const over = indexAt(width / 2, y);
        if (from < 0 || over < 0) return;
        const to = Math.min(over, pinnedCount - 1);
        if (to !== from && to >= 0) keys.move(from, to, 1);
    }

    function dropDragged() {
        const order = [];
        for (let i = 0; i < keys.count; ++i) order.push(keys.get(i).key);
        dragKey = "";
        PinnedApps.setOrder(order);
        sync();
    }
    Component.onCompleted: sync()

    clip: true
    spacing: 4
    interactive: dragKey === "" && contentHeight > height
    boundsBehavior: Flickable.StopAtBounds
    model: keys

    delegate: WindowButton {
        id: button
        required property string key
        group: list.groupOf(key)
        window: list.window
        tooltip: list.tooltip
        width: ListView.view.width
        z: list.dragKey === key ? 1 : 0

        DragHandler {
            target: null
            xAxis.enabled: false
            enabled: button.pinned
            onActiveChanged: {
                if (active) {
                    if (list.tooltip) list.tooltip.hide();
                    list.dragKey = button.key;
                } else if (list.dragKey === button.key) {
                    list.dropDragged();
                }
            }
            onCentroidChanged: {
                if (active) list.dragTo(button.mapToItem(list.contentItem, centroid.position.x, centroid.position.y).y);
            }
        }
    }

    add: Transition {
        NumberAnimation { property: "scale"; from: 0.5; to: 1; duration: Theme.animNormal; easing.type: Easing.OutBack }
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.animFast }
    }
    remove: Transition {
        NumberAnimation { property: "scale"; to: 0.5; duration: Theme.animFast }
        NumberAnimation { property: "opacity"; to: 0; duration: Theme.animFast }
    }
    displaced: Transition {
        NumberAnimation { property: "y"; duration: Theme.animNormal; easing.type: Easing.OutCubic }
    }
}
