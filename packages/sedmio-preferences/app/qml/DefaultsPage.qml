import QtQuick
import Sedmio.Preferences

// «Программы по умолчанию»: чем открывать ссылки, почту, папки, музыку,
// видео, фото, PDF и текст. Применяется сразу.
Page {
    id: root
    title: "Программы по умолчанию"

    Defaults { id: defaults }

    Card {
        Repeater {
            model: defaults.categories
            delegate: Setting {
                id: row
                required property var modelData
                required property int index
                label: modelData.title
                hint: modelData.apps.length === 0 ? "Подходящих программ нет" : ""
                last: index === defaults.categories.length - 1
                Choice {
                    visible: row.modelData.apps.length > 0
                    model: row.modelData.apps.map(a => a.name)
                    currentIndex: row.modelData.current
                    onActivated: index => defaults.choose(row.modelData.id, row.modelData.apps[index].id)
                }
            }
        }
    }

    SButton {
        text: "Для отдельных типов файлов — в параметрах KDE"
        onClicked: App.openKde("kcm_filetypes")
    }
}
