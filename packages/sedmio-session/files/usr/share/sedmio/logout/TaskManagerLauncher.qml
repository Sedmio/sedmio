import QtQuick

// Кнопка «Диспетчер задач» на экране выхода (Ctrl+Alt+Del, как в Windows):
// запускает sedmio-session-manager (sedmioSession). Нет его или самого
// диспетчера — кнопки нет, экран работает.
Item {
    id: root
    signal started()

    readonly property bool available: typeof sedmioSession !== "undefined" && sedmioSession.taskManagerAvailable

    function run() {
        if (available && sedmioSession.launchTaskManager())
            started();
    }
}
