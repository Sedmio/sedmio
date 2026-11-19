import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Sedmio.Style

// Спросить перед тем, что не отменить: удалить навсегда, очистить корзину.
Popup {
    id: dialog
    property string title
    property string text
    property string confirmText: "Удалить"
    property var onConfirm: null

    function ask(title, text, confirmText, action) {
        dialog.title = title;
        dialog.text = text;
        dialog.confirmText = confirmText;
        dialog.onConfirm = action;
        open();
    }

    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(420, parent.width - 40)
    modal: true
    focus: true
    padding: 22
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    Overlay.modal: Rectangle { color: Qt.rgba(0.11, 0.14, 0.12, 0.25) }

    enter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.animFast } }
    exit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 90 } }

    background: Rectangle {
        radius: 16
        color: Theme.surface
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Theme.shadow
            shadowOpacity: 0.25
            shadowBlur: 0.8
            shadowVerticalOffset: 4
        }
    }

    contentItem: ColumnLayout {
        spacing: 10
        focus: true
        Keys.onReturnPressed: confirm.clicked()
        Keys.onEnterPressed: confirm.clicked()

        SText {
            Layout.fillWidth: true
            text: dialog.title
            size: 17
            weight: 650
            wrapMode: Text.Wrap
        }
        SText {
            Layout.fillWidth: true
            text: dialog.text
            color: Theme.inkSoft
            wrapMode: Text.Wrap
            visible: text !== ""
        }
        RowLayout {
            Layout.topMargin: 10
            Layout.alignment: Qt.AlignRight
            spacing: 8
            SButton {
                text: "Отмена"
                onClicked: dialog.close()
            }
            SButton {
                id: confirm
                danger: true
                text: dialog.confirmText
                onClicked: {
                    dialog.close();
                    if (dialog.onConfirm) dialog.onConfirm();
                }
            }
        }
    }
}
