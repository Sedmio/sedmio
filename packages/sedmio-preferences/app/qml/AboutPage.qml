import QtQuick
import Sedmio.Preferences

// «О системе»: имя компьютера (можно переименовать) и сведения о системе
// и железе — с кнопкой «Скопировать» для вопросов на форумах.
Page {
    id: root
    title: "О системе"

    SystemInfo { id: system }

    readonly property var facts: [
        { label: "Система", value: system.osName },
        { label: "Процессор", value: system.cpu },
        { label: "Память", value: system.memory },
        { label: "Видеокарта", value: system.gpu },
        { label: "Диск", value: system.disk },
        { label: "Ядро", value: system.kernel }
    ].filter(f => f.value !== "")

    Row {
        spacing: 18
        SIcon {
            name: "sedmio"
            size: 72
        }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            SText { text: system.osName; size: 20; weight: 650 }
            SText { text: system.hostname; color: Theme.inkSoft }
        }
    }

    Card {
        title: "Имя компьютера"
        Setting {
            last: true
            label: "Так компьютер видно в сети"
            hint: name.text !== "" && !system.validHostname(name.text)
                ? "Только латинские буквы, цифры и дефис (не в начале и не в конце)." : ""
            Row {
                spacing: 8
                SField {
                    id: name
                    width: 220
                    text: system.hostname
                    invalid: text !== "" && !system.validHostname(text)
                    onAccepted: rename.clicked()
                }
                SButton {
                    id: rename
                    text: "Переименовать"
                    primary: true
                    opacity: name.text !== system.hostname && system.validHostname(name.text) ? 1 : 0.45
                    onClicked: if (opacity === 1) system.setHostname(name.text)
                }
            }
        }
    }

    Card {
        title: "Сведения"
        Repeater {
            model: root.facts
            delegate: Setting {
                required property var modelData
                required property int index
                label: modelData.label
                last: index === root.facts.length - 1
                SText {
                    width: Math.min(implicitWidth, 420)
                    text: parent.parent.modelData.value
                    horizontalAlignment: Text.AlignRight
                    wrapMode: Text.Wrap
                    color: Theme.inkSoft
                }
            }
        }
    }

    SText {
        visible: system.error !== ""
        width: parent.width
        text: system.error
        color: Theme.terracotta
        wrapMode: Text.Wrap
    }

    SButton {
        text: "Скопировать сведения"
        onClicked: {
            clipboard.text = root.facts.map(f => f.label + ": " + f.value).join("\n");
            clipboard.selectAll();
            clipboard.copy();
            text = "Скопировано";
        }
    }

    // Буфер обмена из QML — только через текстовое поле.
    TextEdit { id: clipboard; visible: false }
}
