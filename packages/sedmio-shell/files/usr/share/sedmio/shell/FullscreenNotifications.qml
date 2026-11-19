import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import Quickshell.Wayland
import Sedmio.Style

// Срочные уведомления (батарея садится) и сорвавшиеся операции с файлами
// (копирование на флешку не удалось) поверх окна во весь экран: обычные
// карточки — в рамке, а она тогда под окном. Остальные уведомления и ход
// копирования, как в Windows, игре и видео не мешают — ждут в рамке.
// Ловит мышь только на самих карточках; фокус клавиатуры не берёт.
PanelWindow {
    id: root

    readonly property var urgent: NotificationState.popups.filter(n => n.urgency === NotificationUrgency.Critical)
    readonly property var failed: JobsState.popups.filter(j => j.state === "finished" && j.error !== 0)

    // Имя экрана — снаружи (см. FullscreenOsd).
    required property string screenName

    visible: (urgent.length > 0 || failed.length > 0) && ShellState.fullscreenOn(screenName)
    anchors.top: true
    anchors.right: true
    margins.top: 12
    margins.right: 12
    implicitWidth: 380
    implicitHeight: Math.max(1, cards.implicitHeight)
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    mask: Region { item: cards }
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "sedmio-notifications"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Column {
        id: cards
        width: parent.width
        spacing: 8

        Repeater {
            model: ScriptModel { values: root.failed }
            JobCard {
                required property var modelData
                job: modelData
                width: cards.width
            }
        }

        Repeater {
            model: ScriptModel { values: root.urgent }
            NotificationCard {
                required property var modelData
                notification: modelData
                width: cards.width
            }
        }
    }
}
