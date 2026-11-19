pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Порядок кнопок внизу панели (раскладка, сеть, звук, часы…) — меняется
// перетаскиванием (Bar.qml). Хранится в ~/.config/sedmio/bar.json; файла
// нет — порядок по умолчанию. Кнопки, которых в файле нет (появились в
// новой версии), встают на своё место из порядка по умолчанию.
Singleton {
    id: root

    readonly property var defaults: ["keyboard", "network", "battery", "brightness",
        "volume", "notifications", "clock", "settings"]
    property var keys: defaults

    readonly property string path:
        (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config")
        + "/sedmio/bar.json"

    function normalize(saved) {
        const known = saved.filter((key, i) => defaults.includes(key) && saved.indexOf(key) === i);
        for (let i = 0; i < defaults.length; ++i) {
            if (known.includes(defaults[i])) continue;
            // Перед первой из следующих по умолчанию, что уже есть.
            let at = known.length;
            for (let j = i + 1; j < defaults.length; ++j) {
                const k = known.indexOf(defaults[j]);
                if (k >= 0) { at = k; break; }
            }
            known.splice(at, 0, defaults[i]);
        }
        return known;
    }

    FileView {
        id: file
        path: root.path
        printErrors: false   // файла нет, пока порядок не меняли
        onLoaded: {
            try {
                const data = JSON.parse(text());
                root.keys = root.normalize(Array.isArray(data.order) ? data.order : []);
            } catch (e) {
                root.keys = root.defaults;
            }
        }
        onLoadFailed: root.keys = root.defaults
    }

    function setOrder(order) {
        const next = normalize(order);
        if (JSON.stringify(next) === JSON.stringify(keys)) return;
        keys = next;
        file.setText(JSON.stringify({ order: keys }, null, 2) + "\n");
    }
}
