pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Sedmio.Style

// Макет рабочего стола — где что стоит (тема — как выглядит):
//   "left"    — полоса слева, встроенная в рамку вокруг экрана;
//   "dock"    — сверху тонкая панель, снизу док по центру; док прячется,
//               пока на экране развёрнуто окно;
//   "taskbar" — сверху тонкая панель, снизу панель задач на всю ширину.
// Выбор — первая строка ~/.config/sedmio/layout (пишут «Параметры» →
// «Тема»). Файла нет или в нём неизвестное имя — "left". Дальше в файле
// могут быть размеры панелей: "left=48", "top=40", "dock=52",
// "taskbar=44" (толщина в пикселях; нет строки или число вне пределов
// sizes — берётся своё по умолчанию). Файл меняют — всё меняется на ходу.
Singleton {
    id: root

    readonly property var known: ["left", "dock", "taskbar"]
    property string current: "left"

    readonly property bool left: current === "left"
    readonly property bool dock: current === "dock"
    readonly property bool taskbar: current === "taskbar"
    // Сверху панель: в "dock" и "taskbar".
    readonly property bool topBar: !left

    // Толщина каждой панели: по умолчанию и пределы ползунка в «Параметрах»
    // (там те же числа — themes.cpp).
    readonly property var sizes: ({
        left: { def: Theme.barWidth, min: 40, max: 72 },
        top: { def: 40, min: 32, max: 56 },
        dock: { def: Theme.buttonSize + 16, min: 44, max: 96 },
        taskbar: { def: 44, min: 36, max: 64 }
    })
    property var custom: ({})
    function size(key) {
        const v = custom[key], r = sizes[key];
        return Number.isInteger(v) && v >= r.min && v <= r.max ? v : r.def;
    }

    readonly property int leftWidth: size("left")
    readonly property int topBarHeight: size("top")
    readonly property int dockHeight: size("dock")
    readonly property int taskbarHeight: size("taskbar")
    readonly property int dockMargin: 8

    // Кнопки панели растут вместе с ней.
    readonly property int leftButton: leftWidth - 12
    readonly property int topButton: topBarHeight - 4
    readonly property int dockButton: dockHeight - 16
    readonly property int taskbarButton: taskbarHeight - 8

    // Толщина рамки с каждой стороны — проём, в котором окна программ.
    readonly property int insetLeft: left ? leftWidth : 0
    readonly property int insetTop: left ? Theme.border : topBarHeight
    readonly property int insetRight: left ? Theme.border : 0
    readonly property int insetBottom: left ? Theme.border : taskbar ? taskbarHeight : 0
    // Края проёма: в рамке скруглены, у панелей сверху и снизу — прямые.
    readonly property int holeRadius: left ? Theme.frameRadius : 0

    readonly property string path:
        (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config")
        + "/sedmio/layout"

    function reload() { file.reload(); }

    function apply(text) {
        const lines = (text || "").split("\n");
        const name = lines[0].trim();
        current = known.includes(name) ? name : "left";
        const c = {};
        for (const line of lines.slice(1)) {
            const m = line.trim().match(/^(\w+)\s*=\s*(\d+)$/);
            if (m) c[m[1]] = parseInt(m[2]);
        }
        custom = c;
    }

    // text() с blockLoading ждёт, пока файл прочитается; нет файла — "".
    Component.onCompleted: apply(file.text())

    FileView {
        id: file
        path: root.path
        printErrors: false   // файла нет, пока макет не выбирали
        // Читается сразу (blockLoading) и применяется при создании
        // (Component.onCompleted ниже), до первых окон: сигнал loaded
        // приходит позже, окна успевали создаться с макетом "left" по
        // умолчанию, и его зоны (Exclusions) оставались в KWin — сброс
        // левой и правой в 0 сразу после создания окна терялся, у окон
        // было пустое место слева.
        blockLoading: true
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.apply(text())
        onLoadFailed: { root.current = "left"; root.custom = {}; }
    }
}
