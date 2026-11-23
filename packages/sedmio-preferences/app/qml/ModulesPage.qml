import QtQuick
import Sedmio.Style

// «Модули»: части системы, которые можно выключить (Modules). Всё
// меняется сразу, без перезахода.
Page {
    id: root
    title: "Модули"

    Modules { id: modules }

    SText {
        width: parent.width
        text: "Части системы, которые можно выключить. Включаются и выключаются сразу."
        color: Theme.inkMuted
        wrapMode: Text.Wrap
    }

    SText {
        width: parent.width
        visible: modules.message !== ""
        text: modules.message
        color: Theme.terracotta
        wrapMode: Text.Wrap
    }

    Repeater {
        model: modules.groups
        Card {
            id: group
            required property var modelData
            title: modelData.name
            Repeater {
                model: group.modelData.model
                Setting {
                    id: row
                    required property var entry
                    required property int index
                    label: entry.name
                    hint: entry.description
                    last: index === group.modelData.model.count - 1
                    SSwitch {
                        checked: row.entry.enabled
                        onToggled: modules.setEnabled(row.entry.id, !checked)
                    }
                }
            }
        }
    }
}
