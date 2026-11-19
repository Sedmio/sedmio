pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Поиск программ для запуска: оценка совпадения, раскладка, частота.
// И, как «Выполнить» (Win+R) в Windows, — команда, папка или адрес.
Singleton {
    id: root

    // Сколько раз запускали программу: { "org.kde.dolphin": 12, ... }.
    // Часто запускаемые поднимаются выше. Хранится между сеансами.
    property var launches: ({})
    // Последние выполненные команды, новые первыми — подсказываются по началу.
    property var commands: []

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
                root.commands = Array.isArray(data.commands) ? data.commands : [];
            } catch (e) {
                root.launches = {};
                root.commands = [];
            }
        }
    }

    function save() {
        stateFile.setText(JSON.stringify({ launches: launches, commands: commands }, null, 2));
    }

    // Имена программ из PATH: строка «Выполнить» появляется, только если
    // первое слово — такая программа (иначе она была бы на любой запрос).
    property var executables: ({})

    Process {
        id: pathScan
        command: ["sh", "-c", 'IFS=:; for d in $PATH; do [ -d "$d" ] && ls -1 -- "$d"; done 2>/dev/null']
        stdout: StdioCollector {
            onStreamFinished: {
                const names = {};
                for (const name of text.split("\n")) if (name) names[name] = true;
                root.executables = names;
            }
        }
    }

    // Перечитать PATH: зовёт окно запуска при открытии (программы ставят и удаляют).
    function rescan() {
        if (!pathScan.running) pathScan.running = true;
    }

    function launch(entry, inTerminal) {
        if (entry.run) {
            run(entry, inTerminal);
            return;
        }
        const counts = Object.assign({}, launches);
        counts[entry.id] = (counts[entry.id] || 0) + 1;
        launches = counts;
        save();
        // Terminal=true (консольные программы) — в Konsole.
        const command = [];
        if (entry.runInTerminal) command.push("konsole", "-e");
        for (let i = 0; i < entry.command.length; i++) command.push(entry.command[i]);
        ShellState.launch(entry.id, command, entry.workingDirectory);
    }

    // Строка «Выполнить»: путь или адрес — открыть; команда из PATH — выполнить.
    function runEntry(text) {
        if (/^(~|\/|www\.|[a-z][a-z0-9+.-]*:\/\/)/i.test(text))
            return { run: true, open: true, text: text, name: text, genericName: "Открыть",
                     icon: /^(\/|~)/.test(text) ? "folder" : "internet-web-browser" };
        if (!executables[text.split(/\s+/)[0]]) return null;
        return { run: true, open: false, text: text, name: text,
                 genericName: "Выполнить · Ctrl+Enter — в терминале", icon: "utilities-terminal" };
    }

    function run(entry, inTerminal) {
        const home = Quickshell.env("HOME");
        const recent = commands.filter(c => c !== entry.text);
        recent.unshift(entry.text);
        commands = recent.slice(0, 30);
        save();
        if (entry.open) {
            let target = entry.text.replace(/^~(?=\/|$)/, home);
            if (/^www\./i.test(target)) target = "https://" + target;
            // Исполняемый файл — запустить, остальное — в своей программе.
            ShellState.launch("xdg-open", ["sh", "-c",
                'if [ -f "$1" ] && [ -x "$1" ]; then exec "$1"; fi; exec xdg-open "$1"', "sh", target], home);
            return;
        }
        const id = entry.text.split(/\s+/)[0].split("/").pop();
        const command = inTerminal ? ["konsole", "--hold", "-e", "sh", "-c", entry.text]
                                   : ["sh", "-c", entry.text];
        ShellState.launch(id, command, home);
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

    // Транслит: «fajly», «parametry», «dispetcher» → «Файлы», «Параметры»,
    // «Диспетчер задач». Название и запрос сводятся к одному «скелету»
    // латиницей, где разные способы записи совпадают: й/ы/j/y → i,
    // ш/щ/sh/sch → §, ч/ch → ¢, х/kh/x → h, ю/yu/ju → u, я/ya/ja → a...
    readonly property var cyrToLatin: ({
        "а": "a", "б": "b", "в": "v", "г": "g", "д": "d", "е": "e", "ё": "e", "ж": "zh",
        "з": "z", "и": "i", "й": "j", "к": "k", "л": "l", "м": "m", "н": "n", "о": "o",
        "п": "p", "р": "r", "с": "s", "т": "t", "у": "u", "ф": "f", "х": "kh", "ц": "ts",
        "ч": "ch", "ш": "sh", "щ": "shch", "ъ": "", "ы": "y", "ь": "", "э": "e", "ю": "yu", "я": "ya"
    })
    readonly property var latinRules: [
        [/shch|sch|sh/g, "§"], [/ch/g, "¢"], [/zh/g, "z"], [/kh|x/g, "h"], [/ts/g, "c"],
        [/[yj]u/g, "u"], [/[yj]a/g, "a"], [/[yj][oe]/g, "e"], [/[jy]/g, "i"], [/w/g, "v"]
    ]

    function skeleton(text) {
        let out = "";
        for (const ch of text.toLowerCase()) {
            const latinCh = cyrToLatin[ch];
            out += latinCh === undefined ? ch : latinCh;
        }
        for (const rule of latinRules) out = out.replace(rule[0], rule[1]);
        return out;
    }

    // Совпадение по транслиту; только латинский запрос к русскому названию
    // (латинские названия и так сравниваются как есть).
    function translitScore(entry, query) {
        if (!/^[a-z0-9 ]+$/.test(query) || !/[а-яё]/i.test(entry.name)) return 0;
        const q = skeleton(query);
        const name = skeleton(entry.name);
        if (name.startsWith(q)) return 700;
        if (words(name).some(w => w.startsWith(q))) return 550;
        if (q.length >= 3 && name.includes(q)) return 400;
        if (words(skeleton(entry.genericName || "")).some(w => w.startsWith(q))) return 300;
        return 0;
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
            const s = Math.max(score(e, q), Math.floor(score(e, swapped) * 0.95), translitScore(e, q));
            if (s > 0) scored.push({ entry: e, score: s + Math.min(usage(e), 40) * 3 });
        }
        scored.sort((a, b) => b.score - a.score || a.entry.name.localeCompare(b.entry.name));
        const found = scored.map(x => x.entry);

        // «Выполнить»: набранное и прошлые команды с того же начала.
        const text = query.trim();
        const runs = [];
        const typed = runEntry(text);
        if (typed) runs.push(typed);
        for (const c of commands) {
            if (runs.length >= 4) break;
            if (c !== text && c.startsWith(text)) {
                const old = runEntry(c);
                if (old) runs.push(old);
            }
        }
        // Путь, адрес или команда с аргументами — это не поиск программы:
        // строка первой. Одно слово («firefox») — после программ.
        if (typed && (typed.open || /\s/.test(text))) return runs.concat(found);
        return found.concat(runs);
    }
}
