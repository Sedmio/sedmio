pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Связь окон паролей с оболочкой (другой процесс).
Singleton {
    // Открылось окно пароля — закрыть меню и панели оболочки, чтобы не
    // висели под затемнением. Оболочки нет (запасная Plasma) — не страшно.
    function closeShellPopups() {
        closer.running = false;
        closer.running = true;
    }

    Process {
        id: closer
        // По PID из systemd: после самоперезапуска Quickshell путь настроек
        // (ipc -p) экземпляр уже не находит.
        command: ["sh", "-c", "exec quickshell ipc --pid \"$(systemctl --user show -p MainPID --value sedmio-shell.service)\" call shell closePopups"]
    }
}
