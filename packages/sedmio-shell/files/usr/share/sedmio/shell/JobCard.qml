import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Sedmio.Style

// Карточка операции программы (копирование, перемещение, удаление,
// распаковка): что и куда, полоса хода, объём, скорость, сколько осталось.
// Пока идёт — «Пауза» и «Отмена»; готово — клик открывает папку, куда
// копировали. Крестик всплывающую прячет (операция идёт дальше и видна в
// центре уведомлений), законченную — убирает совсем.
Rectangle {
    id: card
    required property var job
    property bool inHistory: false

    // Нажали на законченную: открылась папка.
    signal activated()

    // Карточка может пережить удалённую операцию на время анимации.
    readonly property bool valid: job !== null && job !== undefined
    readonly property string state_: valid ? job.state : "finished"
    readonly property bool finished: state_ === "finished"
    readonly property bool failed: finished && valid && job.error !== 0
    readonly property bool succeeded: finished && !failed

    implicitHeight: content.implicitHeight + 28
    radius: Theme.radius + 3
    color: Theme.surface
    border.width: failed ? 1 : 0
    border.color: Theme.terracotta

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: card.succeeded && card.valid && card.job.destUrl !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
        onContainsMouseChanged: {
            if (!card.valid) return;
            if (containsMouse) JobsState.hovered = card.job.id;
            else if (JobsState.hovered === card.job.id) JobsState.hovered = -1;
        }
        onClicked: {
            if (!card.valid || !card.succeeded || card.job.destUrl === "") return;
            Qt.openUrlExternally(card.job.destUrl);
            card.activated();
            card.job.dismiss();
        }
    }

    ColumnLayout {
        id: content
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
        spacing: 8

        // Программа и крестик
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            IconImage {
                implicitSize: 20
                source: card.valid ? Icons.path(JobsState.appIcon(card.job), "system-file-manager") : ""
            }
            SText {
                Layout.fillWidth: true
                text: card.valid ? JobsState.appName(card.job) : ""
                elide: Text.ElideRight
                size: Theme.fontSmall
                weight: 550
                color: Theme.inkMuted
            }
            Rectangle {
                // В центре уведомлений идущую операцию не спрятать — только отменить.
                visible: !card.inHistory || card.finished
                implicitWidth: 22
                implicitHeight: 22
                radius: 11
                color: closeArea.containsMouse ? Theme.paperDeep : Qt.alpha(Theme.paperDeep, 0)
                SText {
                    anchors.centerIn: parent
                    text: "✕"
                    size: 11
                    color: Theme.inkSoft
                }
                MouseArea {
                    id: closeArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: if (card.valid) JobsState.hide(card.job)
                }
            }
        }

        // Что делается и над чем
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            SIcon {
                visible: card.finished
                implicitSize: 18
                name: card.failed ? "dialog-error" : "checkmark"
            }
            SText {
                Layout.fillWidth: true
                text: card.valid ? JobsState.title(card.job) : ""
                elide: Text.ElideRight
                size: 15
                weight: 600
            }
            SText {
                visible: !card.finished
                text: card.valid ? card.job.percent + "%" : ""
                size: 13
                weight: 600
                color: card.state_ === "suspended" ? Theme.inkMuted : Theme.green
                font.features: ({ "tnum": 1 })
            }
        }

        SText {
            Layout.fillWidth: true
            visible: text !== ""
            text: card.valid ? JobsState.body(card.job) : ""
            textFormat: Text.PlainText
            wrapMode: card.failed ? Text.Wrap : Text.NoWrap
            maximumLineCount: 3
            elide: card.failed ? Text.ElideRight : Text.ElideMiddle
            size: Theme.fontBody
            color: Theme.inkSoft
        }

        // Полоса хода
        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 2
            visible: !card.finished
            implicitHeight: 6
            radius: 3
            color: Theme.paperDeep

            Rectangle {
                width: card.valid ? parent.width * Math.min(100, card.job.percent) / 100 : 0
                height: parent.height
                radius: 3
                color: card.state_ === "suspended" ? Theme.lineStrong : Theme.green
                Behavior on width { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }
            }
        }

        SText {
            Layout.fillWidth: true
            visible: text !== ""
            text: card.valid ? JobsState.details(card.job) : ""
            elide: Text.ElideRight
            size: 12
            color: Theme.inkMuted
            font.features: ({ "tnum": 1 })
        }

        // Пауза и отмена; у законченной — «Открыть папку»
        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            visible: card.valid && (!card.finished ? (card.job.suspendable || card.job.killable)
                : card.succeeded && card.job.destUrl !== "")

            Repeater {
                model: !card.valid ? []
                    : card.succeeded ? [{ text: "Открыть папку", action: "open" }]
                    : card.finished ? []
                    : [card.job.suspendable ? (card.state_ === "suspended"
                           ? { text: "Продолжить", action: "resume" } : { text: "Пауза", action: "suspend" }) : null,
                       card.job.killable ? { text: "Отмена", action: "cancel" } : null].filter(b => b !== null)

                Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 32
                    radius: 10
                    color: buttonArea.containsMouse ? Theme.greenWash : Theme.paperDeep
                    SText {
                        anchors.centerIn: parent
                        text: parent.modelData.text
                        size: 13
                        weight: 550
                    }
                    MouseArea {
                        id: buttonArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            if (!card.valid) return;
                            switch (parent.modelData.action) {
                            case "suspend": card.job.suspend(); break;
                            case "resume": card.job.resume(); break;
                            case "cancel": card.job.cancel(); break;
                            case "open":
                                // dismiss() удаляет карточку: после него к ней не обращаться.
                                Qt.openUrlExternally(card.job.destUrl);
                                card.activated();
                                card.job.dismiss();
                                break;
                            }
                        }
                    }
                }
            }
        }
    }
}
