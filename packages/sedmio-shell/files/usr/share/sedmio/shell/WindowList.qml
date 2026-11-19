import QtQuick
import Sedmio.Style

// Открытые окна, по кнопке на программу: окна одной программы — в одной
// кнопке. Диалоги («Свойства», «Сохранить как») не показываем — они всегда
// над своим окном и поднимаются вместе с ним. Список даёт ToplevelManager —
// в нашей сборке Quickshell он работает и под KWin
// (org_kde_plasma_window_management).
ListView {
    id: list
    required property var window
    required property Item tooltip

    // Программы и их окна — в ShellState (по ним же работают Meta+1…9).
    readonly property var groups: ShellState.windowGroups

    function windowsOf(key) {
        const group = groups.find(g => g.key === key);
        return group ? group.windows : [];
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
    onGroupsChanged: sync()
    Component.onCompleted: sync()

    clip: true
    spacing: 4
    boundsBehavior: Flickable.StopAtBounds
    model: keys

    delegate: WindowButton {
        required property string key
        windows: list.windowsOf(key)
        window: list.window
        tooltip: list.tooltip
        width: ListView.view.width
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
