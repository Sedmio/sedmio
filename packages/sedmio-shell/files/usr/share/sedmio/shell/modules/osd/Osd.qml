import QtQuick
import Quickshell
import Quickshell.Widgets
import qs
import Sedmio.Style

// Содержимое всплывающего индикатора (часть "osd"): значок, полоса и
// проценты или значок и подпись. Подложку рисует оболочка: в рамке —
// EdgeDrawerShape, поверх окна во весь экран — FullscreenOsd. shown —
// показать сейчас на этом экране (screenName).
Item {
    id: root
    property string screenName
    readonly property bool shown: OsdState.shown && screenName !== "" && OsdState.screenName === screenName
    readonly property bool progress: OsdState.mode === "progress"

    // Ширина по содержимому: полосе нужно место, подписи — сколько займёт
    // (отступы 16, значок 24, промежуток 12, отступ 16 и запас 4). Вверх
    // до целого: окно округляет ширину вниз, и подпись без запаса
    // обрезалась многоточием.
    readonly property real wantedWidth: progress ? 300 : Math.max(120, Math.min(420, Math.ceil(label.implicitWidth) + 72))

    IconImage {
        id: icon
        anchors.verticalCenter: parent.verticalCenter
        x: 16
        implicitSize: 24
        source: OsdState.icon !== "" ? Icons.path(OsdState.icon, "dialog-information") : ""
    }

    // Полоса
    Item {
        visible: root.progress
        anchors { left: icon.right; leftMargin: 14; right: value.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
        height: 8

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: Theme.paperDeep
        }
        Rectangle {
            readonly property real share: Math.min(1, OsdState.percent / 100)
            width: Math.max(height, parent.width * share)
            height: parent.height
            radius: height / 2
            // Громче 100% — терракотой, как предупреждение.
            color: OsdState.percent > 100 ? Theme.terracotta : Theme.green
            Behavior on width { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
        }
    }

    SText {
        id: value
        visible: root.progress
        anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
        width: 34
        horizontalAlignment: Text.AlignRight
        text: OsdState.percent
        font.features: ({ "tnum": 1 })
        size: 15
        weight: 600
    }

    SText {
        id: label
        visible: !root.progress
        anchors { left: icon.right; leftMargin: 12; right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
        elide: Text.ElideRight
        text: OsdState.text
        size: 15
        weight: 550
    }
}
