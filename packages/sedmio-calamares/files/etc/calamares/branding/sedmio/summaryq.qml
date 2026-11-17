import QtQuick
import io.calamares.core 1.0
import io.calamares.ui 1.0
import "components"

// Итог перед установкой: список «что произойдёт» с тонкими разделителями.
// config: модуль summary (summaryModel: title, message).
SPage {
    id: page

    stage: 5
    centerVertically: false

    function onActivate() { page.replayAppear() }

    PageHeader {
        width: parent.width
        eyebrow: "Почти готово"
        title: "Проверим всё ещё раз"
    }

    Column {
        width: parent.width
        spacing: 0

        Repeater {
            model: config.summaryModel

            delegate: Column {
                width: parent.width
                spacing: 6
                bottomPadding: 16

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Theme.line
                    visible: index > 0
                }
                Item { width: 1; height: index > 0 ? 8 : 0 }

                Text {
                    width: parent.width
                    text: model.title
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSmall
                    font.weight: Font.DemiBold
                    font.letterSpacing: 0.8
                    font.capitalization: Font.AllUppercase
                    color: Theme.inkMuted
                }
                Text {
                    width: parent.width
                    text: model.message
                    textFormat: Text.RichText
                    wrapMode: Text.WordWrap
                    lineHeight: 1.25
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontBody
                    color: Theme.ink
                }
            }
        }
    }

    Message {
        width: parent.width
        kind: "warning"
        text: "После нажатия «Установить» диск будет изменён — отменить это уже не получится."
    }
}
