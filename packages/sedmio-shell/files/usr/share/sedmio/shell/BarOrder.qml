pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Порядок кнопок состояния (раскладка, сеть, звук, часы…) — меняется
// перетаскиванием (StatusButtons). Кнопки — модули с частью "status"
// (Modules), и выключенные тоже: включили снова — кнопка на прежнем
// месте. Хранится в ~/.config/sedmio/bar.json; файла нет — порядок по
// умолчанию (order в module.json). Кнопки, которых в файле нет (новый
// модуль), встают на своё место из порядка по умолчанию.
Singleton {
    id: root

    readonly property var defaults: Modules.allWithPart("status")
    // Как в файле; keys — он же, приведённый к установленным модулям.
    property var saved: []
    readonly property var keys: normalize(saved)

    readonly property string path:
        (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config")
        + "/sedmio/bar.json"

    function normalize(order) {
        const known = order.filter((key, i) => defaults.includes(key) && order.indexOf(key) === i);
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
                root.saved = Array.isArray(data.order) ? data.order : [];
            } catch (e) {
                root.saved = [];
            }
        }
        onLoadFailed: root.saved = []
    }

    function setOrder(order) {
        const next = normalize(order);
        if (JSON.stringify(next) === JSON.stringify(keys)) return;
        // Кнопки модулей, которых сейчас нет (удалён пакет), остаются в
        // файле — в конце: поставят обратно — кнопка в конце ряда.
        const gone = saved.filter(k => !defaults.includes(k));
        saved = next.concat(gone);
        file.setText(JSON.stringify({ order: saved }, null, 2) + "\n");
    }
}
