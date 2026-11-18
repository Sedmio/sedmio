import QtQuick
import QtQuick.Layouts
import Quickshell

// Центр уведомлений: все пришедшие и не закрытые, новые сверху, и
// «Очистить всё». Выезжает справа сверху, там же, где всплывают карточки.
// Подложку рисует DrawerShape в слое рамки, здесь только то, что на ней.
Item {
    id: root
    property bool open: false
    property real maxHeight: 700
    signal closeRequested(bool restoreFocus)

    readonly property var history: NotificationState.history

    readonly property real wantedHeight: Math.min(maxHeight, column.implicitHeight)

    onOpenChanged: {
        if (!open) return;
        list.positionViewAtBeginning();
        keys.forceActiveFocus();
    }

    Item {
        id: keys
        focus: true
        Keys.onEscapePressed: root.closeRequested(true)
    }

    ColumnLayout {
        id: column
        anchors { left: parent.left; right: parent.right; top: parent.top }
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 34
            Layout.leftMargin: 4
            spacing: 8

            SText {
                Layout.fillWidth: true
                text: "Уведомления"
                size: 17
                weight: 650
            }

            SButton {
                visible: root.history.length > 0
                text: "Очистить всё"
                onClicked: NotificationState.clearAll()
            }
        }

        // Пусто
        ColumnLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 18
            Layout.bottomMargin: 22
            visible: root.history.length === 0
            spacing: 8

            SIcon {
                Layout.alignment: Qt.AlignHCenter
                implicitSize: 40
                name: "notifications"
                opacity: 0.35
            }
            SText {
                Layout.alignment: Qt.AlignHCenter
                text: "Нет уведомлений"
                color: Theme.inkMuted
            }
        }

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(contentHeight, root.maxHeight - 130)
            visible: root.history.length > 0
            clip: true
            spacing: 8
            boundsBehavior: Flickable.StopAtBounds

            // ScriptModel меняет список точечно: закрытая карточка уходит,
            // остальные не пересоздаются.
            model: ScriptModel { values: root.history }

            delegate: NotificationCard {
                required property var modelData
                notification: modelData
                inHistory: true
                width: list.width
                onActivated: root.closeRequested(false)
            }

            remove: Transition {
                NumberAnimation { property: "opacity"; to: 0; duration: Theme.animFast }
            }
            displaced: Transition {
                NumberAnimation { property: "y"; duration: Theme.animNormal; easing.type: Easing.OutCubic }
            }
        }

        // «Не беспокоить» — то же, что плитка в панели управления.
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Theme.line
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 4
            Layout.rightMargin: 4
            spacing: 10

            SIcon {
                implicitSize: 18
                name: "notifications-disabled"
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                SText {
                    text: "Не беспокоить"
                    weight: 550
                }
                SText {
                    Layout.fillWidth: true
                    text: NotificationState.doNotDisturb
                        ? "Новые не всплывают, но собираются здесь"
                        : "Срочные всплывают всё равно"
                    wrapMode: Text.Wrap
                    size: 12
                    color: Theme.inkMuted
                }
            }
            SSwitch {
                checked: NotificationState.doNotDisturb
                onToggled: NotificationState.setDoNotDisturb(!checked)
            }
        }
    }
}
