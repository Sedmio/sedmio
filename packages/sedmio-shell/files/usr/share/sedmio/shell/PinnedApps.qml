pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Программы, закреплённые на панели, как в Windows: кнопка есть, даже
// когда программа не запущена; щелчок её запускает. Закрепить и открепить —
// правым щелчком по кнопке, порядок — перетаскиванием. Список — имена .desktop-файлов, по порядку,
// в ~/.config/sedmio/panel.json; файла нет — закреплены «Файлы» и Firefox.
// Не установленные программы панель пропускает (WindowList, ShellState).
Singleton {
    id: root

    readonly property var defaults: ["sedmio-files", "firefox"]
    property var ids: []

    readonly property string path:
        (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config")
        + "/sedmio/panel.json"

    FileView {
        id: file
        path: root.path
        printErrors: false   // файла нет, пока ничего не меняли
        onLoaded: {
            try {
                const data = JSON.parse(text());
                root.ids = Array.isArray(data.pinned)
                    ? data.pinned.filter(id => typeof id === "string" && id !== "")
                    : root.defaults;
            } catch (e) {
                // Файл испорчен — панель с закреплёнными по умолчанию, файл
                // перезапишется при следующем изменении.
                root.ids = root.defaults;
            }
        }
        onLoadFailed: root.ids = root.defaults
    }

    function isPinned(id) {
        return !!id && ids.indexOf(id) !== -1;
    }

    function pin(id) {
        if (!id || isPinned(id)) return;
        ids = ids.concat([id]);
        save();
    }

    function unpin(id) {
        if (!isPinned(id)) return;
        ids = ids.filter(other => other !== id);
        save();
    }

    // Новый порядок закреплённых (перетащили кнопку на панели). Тех, кого
    // в order нет (программа не установлена — кнопки нет), оставляем в конце.
    function setOrder(order) {
        const known = order.filter(id => isPinned(id));
        const rest = ids.filter(id => known.indexOf(id) === -1);
        const next = known.concat(rest);
        if (JSON.stringify(next) === JSON.stringify(ids)) return;
        ids = next;
        save();
    }

    function save() {
        file.setText(JSON.stringify({ pinned: ids }, null, 2) + "\n");
    }
}
