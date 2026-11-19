// Окна паролей Sedmio: администратор (polkit), Wi‑Fi (NetworkManager),
// сопряжение Bluetooth (BlueZ). Отдельный процесс от оболочки — служба
// sedmio-agents.service: упадёт или перезапустится панель, а запрос
// пароля, открытый в этот момент, не пропадёт и новые будут работать.
// Оформление: цвета — Sedmio.Style (sedmio-theme), SText, SButton,
// SIcon — ссылки на ../shell.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Kde
import Quickshell.Services.Polkit

ShellRoot {
    // За файлами не следим, перечитывает хук pacman (как у оболочки):
    //   quickshell ipc -p /usr/share/sedmio/agents call agents reload
    settings.watchFiles: false

    IpcHandler {
        target: "agents"
        function reload(): void { Quickshell.reload(false); }
    }

    // Пароль администратора — вместо polkit-kde-agent, его служба
    // отключена (usr/lib/systemd/user/plasma-polkit-agent.service.d).
    PolkitAgent {
        id: polkit
        onAuthenticationRequestStarted: Agents.closeShellPopups()
    }
    PolkitDialog { agent: polkit }

    // Пароль от Wi‑Fi, когда его просит NetworkManager, — вместо plasma-nm.
    NetworkSecretAgent { id: networkAgent }
    NetworkPasswordDialog { agent: networkAgent }

    // Сопряжение Bluetooth (коды, разрешения) — вместо агента bluedevil.
    BluetoothAgent { id: bluetoothAgent }
    BluetoothPairDialog { agent: bluetoothAgent }
}
