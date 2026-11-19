pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// «Ножницы»: снимок экрана как в Windows 11 (PrtSc, Win+Shift+S —
// /usr/lib/sedmio/screenshot зовёт `call screenshot open`).
// Сначала снимаем все экраны (sedmio-capture, пакет sedmio-screenshot), потом
// показываем снимки поверх (ScreenshotOverlay) — экран как будто замер, и
// выделять можно и то, что сейчас движется или исчезнет от щелчка (меню,
// подсказки). Вырезает и сохраняет /usr/lib/sedmio/screenshot save.
Singleton {
    id: root

    // Снимки на экране; mode — что выделяем: "region" | "screen".
    property bool active: false
    property bool capturing: false
    property string mode: "region"
    // Экран с полоской режимов (где была клавиатура).
    property string toolbarScreen: ""
    // {имя экрана: {file, width, height}} — width, height в точках снимка.
    property var shots: ({})

    readonly property string dir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/sedmio-screenshot"

    function open() {
        if (active || capturing) return;
        ShellState.closeAll(false);
        toolbarScreen = ShellState.focusedScreen();
        mode = "region";
        capturing = true;
        grab.command = ["/usr/lib/sedmio/sedmio-capture", "screens", dir]
            .concat(Quickshell.screens.map(s => s.name));
        grab.running = true;
    }

    function close() {
        active = false;
        shots = {};
        cleanup.running = true;
    }

    // Вырезать rect (в точках экрана) со снимка экрана screenName.
    function save(screenName, rect, screenWidth, screenHeight) {
        const shot = shots[screenName];
        if (!shot || rect.width < 1 || rect.height < 1) return;
        const sx = shot.width / screenWidth, sy = shot.height / screenHeight;
        const x = Math.max(0, Math.round(rect.x * sx)), y = Math.max(0, Math.round(rect.y * sy));
        const w = Math.min(shot.width - x, Math.round(rect.width * sx));
        const h = Math.min(shot.height - y, Math.round(rect.height * sy));
        active = false;
        // Временные снимки удаляет cleanup — после того как save вырезал.
        saver.command = ["/usr/lib/sedmio/screenshot", "save", shot.file, String(x), String(y), String(w), String(h)];
        saver.running = true;
    }

    function saveScreen(screenName) {
        const shot = shots[screenName];
        if (!shot) return;
        active = false;
        saver.command = ["/usr/lib/sedmio/screenshot", "save", shot.file, "0", "0", String(shot.width), String(shot.height)];
        saver.running = true;
    }

    // Окно: снимки убрать, окно выбирают щелчком (KWin), Esc — отмена.
    function pickWindow() {
        close();
        Quickshell.execDetached(["/usr/lib/sedmio/screenshot", "pick-window"]);
    }

    Process {
        id: grab
        stdout: StdioCollector { id: grabOut }
        onExited: code => {
            root.capturing = false;
            let shots = {};
            try {
                shots = JSON.parse(grabOut.text || "{}");
            } catch (e) {
                shots = {};
            }
            if (Object.keys(shots).length === 0) {
                console.warn("screenshot: sedmio-capture не снял экраны, код", code);
                return;
            }
            root.shots = shots;
            root.active = true;
        }
    }

    Process {
        id: saver
        onExited: cleanup.running = true
    }

    Process {
        id: cleanup
        command: ["rm", "-rf", root.dir]
    }
}
