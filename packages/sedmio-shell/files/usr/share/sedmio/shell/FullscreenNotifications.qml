import QtQuick
import Quickshell
import Quickshell.Wayland
import Sedmio.Style

// Срочные уведомления (батарея садится) и сорвавшиеся операции с файлами
// (копирование на флешку не удалось) поверх окна во весь экран: обычные
// карточки — в рамке, а она тогда под окном. Остальные уведомления и ход
// копирования, как в Windows, игре и видео не мешают — ждут в рамке.
// Ловит мышь только на самих карточках; фокус клавиатуры не берёт.
PanelWindow {
    id: root

    readonly property var failed: JobsState.popups.filter(j => j.state === "finished" && j.error !== 0)

    // Имя экрана — снаружи (см. FullscreenOsd).
    required property string screenName

    readonly property int urgent: urgentCards.item ? urgentCards.item.count : 0
    visible: (urgent > 0 || failed.length > 0) && ShellState.fullscreenOn(screenName)
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

        // Срочные — часть "popups" модуля уведомлений.
        ModulePart {
            id: urgentCards
            module: Modules.withPart("popups")[0] ?? ""
            part: "popups"
            props: ({ urgentOnly: true })
            width: cards.width
            visible: root.urgent > 0
        }
    }
}
