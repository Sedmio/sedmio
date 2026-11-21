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
// «Тема»). Файла нет или в нём неизвестное имя — "left". Файл меняют —
// макет меняется на ходу.
Singleton {
    id: root

    readonly property var known: ["left", "dock", "taskbar"]
    property string current: "left"

    readonly property bool left: current === "left"
    readonly property bool dock: current === "dock"
    readonly property bool taskbar: current === "taskbar"
    // Сверху панель: в "dock" и "taskbar".
    readonly property bool topBar: !left

    readonly property int topBarHeight: 40
    readonly property int taskbarHeight: 48
    readonly property int dockHeight: Theme.buttonSize + 16
    readonly property int dockMargin: 8

    // Толщина рамки с каждой стороны — проём, в котором окна программ.
    readonly property int insetLeft: left ? Theme.barWidth : 0
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
        const name = (text || "").split("\n")[0].trim();
        current = known.includes(name) ? name : "left";
    }

    FileView {
        id: file
        path: root.path
        printErrors: false   // файла нет, пока макет не выбирали
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.apply(text())
        onLoadFailed: root.current = "left"
    }
}
