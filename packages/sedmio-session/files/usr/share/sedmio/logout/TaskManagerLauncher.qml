import QtQuick

// Кнопка «Диспетчер задач» на экране выхода (Ctrl+Alt+Del, как в Windows).
// В сеансе Sedmio запускает sedmio-session-manager (sedmioSession); в окне
// выхода Plasma (запасной путь) — через plasma5support, файлом из пакета
// org.sedmio.shell. Нет ни того, ни другого — кнопки нет, экран работает.
Item {
    id: root
    signal started()

    readonly property bool ours: typeof sedmioSession !== "undefined"
    readonly property bool available: ours ? sedmioSession.taskManagerAvailable
        : plasma.status === Loader.Ready && plasma.item.available

    function run() {
        if (ours) {
            if (sedmioSession.launchTaskManager()) started();
        } else if (plasma.item) {
            plasma.item.run();
        }
    }

    Loader {
        id: plasma
        active: !root.ours
        source: "file:///usr/share/plasma/shells/org.sedmio.shell/contents/logout/PlasmaTaskManager.qml"
    }
    Connections {
        target: plasma.item
        ignoreUnknownSignals: true
        function onStarted() { root.started(); }
    }
}
