pragma Singleton
import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io

// Модули оболочки: всё, что можно выключить, — папка modules/<id> с
// описанием module.json (поля — modules/README.md). Модули ставит любой
// пакет; что включено — решает пользователь: ~/.config/sedmio/modules,
// строки "<id>=on|off" (пишут sedmio-modules и «Параметры» → «Модули»).
// Строки нет — как сказано в описании ("default", по умолчанию включён).
// Файл меняют — модули включаются и выключаются на ходу.
//
// Части модуля грузит ModulePart: "status" — кнопка в ряду состояния
// (StatusButtons), "screen" — по одной на экран, "main" — одна на всю
// оболочку (shell.qml). Сломанный модуль просто не загружается.
Singleton {
    id: root

    // {id: описание}; id — имя папки.
    property var manifests: ({})
    // {id: true|false} — решения пользователя.
    property var choices: ({})

    // Описания по порядку (order, потом название).
    readonly property var list: Object.keys(manifests).map(id => manifests[id])
        .sort((a, b) => (a.order ?? 100) - (b.order ?? 100) || a.name.localeCompare(b.name))

    function on(id) {
        const m = manifests[id];
        if (!m) return false;
        return id in choices ? choices[id] : m.default !== false;
    }
    // Включённые модули с этой частью, по порядку.
    function withPart(part) { return list.filter(m => m[part] && on(m.id)).map(m => m.id); }
    // Все модули с этой частью, и выключенные тоже (порядок кнопок их помнит).
    function allWithPart(part) { return list.filter(m => m[part]).map(m => m.id); }
    function url(id, part) {
        const m = manifests[id];
        return m && m[part] ? Qt.resolvedUrl("modules/" + id + "/" + m[part]) : "";
    }

    readonly property string dir: Quickshell.shellPath("modules")
    // Имя папки = имя модуля QML (import qs.modules.<id>): без дефисов.
    function valid(id) { return /^[a-z][a-z0-9_]*$/.test(id); }

    function add(id, text) {
        let m;
        try {
            m = JSON.parse(text);
        } catch (e) {
            console.warn("Модуль", id + ": module.json не читается:", e);
            return;
        }
        if (typeof m !== "object" || m === null || typeof m.name !== "string") {
            console.warn("Модуль", id + ": в module.json нет названия (name)");
            return;
        }
        m.id = id;
        const next = Object.assign({}, manifests);
        next[id] = m;
        manifests = next;
    }
    function drop(id) {
        if (!(id in manifests)) return;
        const next = Object.assign({}, manifests);
        delete next[id];
        manifests = next;
    }

    FolderListModel {
        id: folders
        folder: "file://" + root.dir
        showFiles: false
        showDirs: true
        showHidden: false
    }

    Instantiator {
        model: folders
        delegate: FileView {
            required property string fileName
            readonly property string moduleId: fileName
            path: root.valid(fileName) ? root.dir + "/" + fileName + "/module.json" : ""
            printErrors: false   // папка без описания — не модуль
            onLoaded: root.add(moduleId, text())
            onLoadFailed: root.drop(moduleId)
            Component.onDestruction: root.drop(moduleId)
        }
    }

    readonly property string path:
        (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config")
        + "/sedmio/modules"

    function apply(text) {
        const c = {};
        for (const line of (text || "").split("\n")) {
            const m = line.trim().match(/^([a-z][a-z0-9_]*)\s*=\s*(on|off)$/);
            if (m) c[m[1]] = m[2] === "on";
        }
        choices = c;
    }

    // Файл заменяют целиком (sedmio-modules, «Параметры») — слежение за ним
    // при этом может отвалиться, поэтому они ещё и зовут
    //   quickshell ipc -p /usr/share/sedmio/shell call modules reload
    function reload() { choicesFile.reload(); }

    Component.onCompleted: apply(choicesFile.text())

    FileView {
        id: choicesFile
        path: root.path
        printErrors: false   // файла нет, пока ничего не переключали
        blockLoading: true   // выключенные кнопки не мелькают при запуске
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.apply(text())
        onLoadFailed: root.choices = {}
    }
}
