import QtQuick
import io.calamares.core 1.0
import io.calamares.ui 1.0
import "components"

// Приветствие и проверка компьютера.
// config: модуль welcome (requirementsModel).
SPage {
    id: page

    stage: 1

    readonly property var req: config.requirementsModel

    function onActivate() { page.replayAppear() }

    PageHeader {
        width: parent.width
        eyebrow: "Sedmio Linux"
        title: "Привет! Давайте установим Sedmio"
        subtitle: "Это займёт минут десять. Растение справа будет расти вместе с установкой."
    }

    Column {
        width: parent.width
        spacing: 14

        Text {
            text: "Проверили компьютер"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSmall
            font.weight: Font.DemiBold
            color: Theme.inkMuted
        }

        Repeater {
            model: page.req
            delegate: Message {
                width: parent.width
                kind: model.satisfied ? "ok" : (model.mandatory ? "error" : "warning")
                text: model.satisfied ? model.details : model.negatedText
            }
        }

        Text {
            visible: page.req.progressMessage !== ""
            width: parent.width
            text: page.req.progressMessage
            wrapMode: Text.WordWrap
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSmall
            color: Theme.inkMuted
        }
    }

    Message {
        width: parent.width
        visible: !page.req.satisfiedMandatory
        kind: "error"
        text: "Дальше пройти нельзя, пока не исправлены пункты с восклицательным знаком."
    }
}
