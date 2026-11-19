import QtQuick
import org.kde.plasma.plasma5support as P5Support

// Запуск диспетчера задач с экрана выхода в окне выхода Plasma (запасной
// путь; см. Logout.qml и /usr/share/sedmio/logout/TaskManagerLauncher.qml).
// Отдельным файлом: нет модуля plasma5support — пропадёт только кнопка,
// а не весь экран. kstart запускает программу как из меню (своя служба
// systemd) и сразу выходит, так что экран можно закрыть после него.
P5Support.DataSource {
    id: source
    engine: "executable"
    signal started()
    // Есть ли сама программа (пакет sedmio-tasks); нет — кнопку не показывать.
    property bool available: false

    readonly property string check: "test -x /usr/bin/sedmio-tasks"
    readonly property string launch: "kstart --application sedmio-tasks || setsid -f sedmio-tasks"

    Component.onCompleted: connectSource(check)

    function run() {
        connectSource(launch);
        fallback.start();
    }

    onNewData: (sourceName, data) => {
        disconnectSource(sourceName);
        if (sourceName === check) {
            available = data["exit code"] === 0;
            return;
        }
        fallback.stop();
        started();
    }

    // kstart не ответил — всё равно закрыть экран.
    property Timer fallback: Timer {
        interval: 3000
        onTriggered: source.started()
    }
}
