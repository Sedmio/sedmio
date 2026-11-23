import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import qs
import Sedmio.Style

// Всплывающие карточки (часть "popups"), новые сверху. Оболочка ставит
// их справа сверху под карточками операций; urgentOnly — только срочные,
// поверх окна во весь экран (FullscreenNotifications). count — сколько
// карточек сейчас, по нему оболочка решает, выдвигать ли ящик.
Column {
    id: root
    property bool urgentOnly: false
    readonly property var cards: urgentOnly
        ? NotificationState.popups.filter(n => n.urgency === NotificationUrgency.Critical)
        : NotificationState.popups
    readonly property int count: cards.length

    spacing: 8

    add: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.animNormal }
    }
    move: Transition {
        NumberAnimation { property: "y"; duration: Theme.animNormal; easing.type: Easing.OutCubic }
    }

    Repeater {
        // ScriptModel меняет список точечно: карточки не пересоздаются и
        // их таймеры не сбрасываются.
        model: ScriptModel { values: root.cards }
        NotificationCard {
            required property var modelData
            notification: modelData
            width: root.width
        }
    }
}
