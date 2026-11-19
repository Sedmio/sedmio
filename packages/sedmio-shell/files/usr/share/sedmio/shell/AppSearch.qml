pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Поиск программ для запуска: оценка совпадения, раскладка, частота.
Singleton {
    id: root

    // Сколько раз запускали программу: { "org.kde.dolphin": 12, ... }.
    // Часто запускаемые поднимаются выше. Хранится между сеансами.
    property var launches: ({})

    readonly property string statePath:
        (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state")
        + "/sedmio/launcher.json"

    FileView {
        id: stateFile
        path: root.statePath
        printErrors: false   // файла нет до первого запуска программы
        onLoaded: {
            try {
                const data = JSON.parse(text());
                root.launches = data.launches || {};
            } catch (e) {
                root.launches = {};
            }
        }
    }

    function launch(entry) {
        const counts = Object.assign({}, launches);
        counts[entry.id] = (counts[entry.id] || 0) + 1;
        launches = counts;
        stateFile.setText(JSON.stringify({ launches: counts }, null, 2));
        // Terminal=true (консольные программы) — в Konsole.
        const command = [];
        if (entry.runInTerminal) command.push("konsole", "-e");
        for (let i = 0; i < entry.command.length; i++) command.push(entry.command[i]);
        ShellState.launch(entry.id, command, entry.workingDirectory);
    }

    // Запрос, набранный не в той раскладке: «ашкуащч» → «firefox».
    readonly property string latin: "qwertyuiop[]asdfghjkl;'zxcvbnm,.`"
    readonly property string cyrillic: "йцукенгшщзхъфывапролджэячсмитьбюё"

    function switchLayout(text) {
        let out = "";
        for (const ch of text) {
            let i = latin.indexOf(ch);
            if (i >= 0) { out += cyrillic[i]; continue; }
            i = cyrillic.indexOf(ch);
            out += i >= 0 ? latin[i] : ch;
        }
        return out;
    }

    function words(text) {
        return text.toLowerCase().split(/[\s\-_.()]+/).filter(w => w.length > 0);
    }

    // Буквы запроса идут в названии по порядку: «впл» → «ВидеоПЛеер».
    function subsequence(text, query) {
        let i = 0;
        for (const ch of text) {
            if (ch === query[i]) i++;
            if (i === query.length) return true;
        }
        return false;
    }

    function score(entry, query) {
        const name = entry.name.toLowerCase();
        const generic = (entry.genericName || "").toLowerCase();

        if (name === query) return 1000;
        if (name.startsWith(query)) return 800;
        if (words(name).some(w => w.startsWith(query))) return 600;
        if (name.includes(query)) return 450;
        if (words(generic).some(w => w.startsWith(query))) return 350;
        if (entry.keywords.some(k => k.toLowerCase().startsWith(query))) return 300;
        if (entry.id.toLowerCase().includes(query)) return 250;
        if (generic.includes(query)) return 200;
        if ((entry.comment || "").toLowerCase().includes(query)) return 100;
        if (query.length >= 2 && subsequence(name, query)) return 50;
        return 0;
    }

    function search(query) {
        const apps = DesktopEntries.applications.values.filter(e => !e.noDisplay && e.name !== "");
        const usage = e => launches[e.id] || 0;
        const q = query.trim().toLowerCase();

        if (q === "") {
            return apps.sort((a, b) => usage(b) - usage(a) || a.name.localeCompare(b.name));
        }

        const swapped = switchLayout(q);
        const scored = [];
        for (const e of apps) {
            const s = Math.max(score(e, q), Math.floor(score(e, swapped) * 0.95));
            if (s > 0) scored.push({ entry: e, score: s + Math.min(usage(e), 40) * 3 });
        }
        scored.sort((a, b) => b.score - a.score || a.entry.name.localeCompare(b.entry.name));
        return scored.map(x => x.entry);
    }
}
