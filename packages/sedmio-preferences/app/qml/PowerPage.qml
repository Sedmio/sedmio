import QtQuick
import Sedmio.Preferences
import Sedmio.Style

// «Питание»: когда затемнять и гасить экран, когда засыпать; что делают
// кнопка питания и крышка. Применяется сразу.
Page {
    id: root
    title: "Питание"

    Power { id: power }

    readonly property var dimSteps: [0, 60, 120, 300, 600, 900]
    readonly property var offSteps: [0, 60, 120, 300, 600, 900, 1800, 3600]
    readonly property var sleepSteps: [0, 300, 600, 900, 1800, 3600, 7200, 10800]

    function label(seconds) {
        if (seconds <= 0) return "Никогда";
        if (seconds < 60) return seconds + " с";
        if (seconds % 3600 === 0) return (seconds / 3600) + " ч";
        return Math.round(seconds / 60) + " мин";
    }
    // Шаги списка плюс нынешнее значение, если его выставили где-то ещё.
    function steps(list, current) {
        if (list.indexOf(current) >= 0) return list;
        return list.concat([current]).sort((a, b) => (a === 0 ? -1 : b === 0 ? 1 : a - b));
    }

    component TimeChoice: Choice {
        id: choice
        required property var profile
        required property string kind
        required property var baseSteps
        readonly property var values: root.steps(baseSteps, profile[kind])
        model: values.map(v => root.label(v))
        currentIndex: values.indexOf(profile[kind])
        onActivated: index => power.setTimeout(profile.id, kind, values[index])
    }

    Repeater {
        model: power.profiles
        delegate: Card {
            id: card
            required property var modelData
            title: power.profiles.length > 1 ? modelData.title : "Экран и сон"
            Setting {
                label: "Затемнять экран"
                TimeChoice { profile: card.modelData; kind: "dim"; baseSteps: root.dimSteps }
            }
            Setting {
                label: "Выключать экран"
                last: !power.canSuspend
                TimeChoice { profile: card.modelData; kind: "off"; baseSteps: root.offSteps }
            }
            Setting {
                visible: power.canSuspend
                last: true
                label: "Переходить в сон"
                TimeChoice { profile: card.modelData; kind: "sleep"; baseSteps: root.sleepSteps }
            }
        }
    }

    Card {
        title: "Кнопки"
        Setting {
            id: buttonRow
            readonly property var actions: power.canSuspend ? [16, 1, 8, 0] : [16, 8, 0]
            readonly property var names: ({ 16: "Спросить, что сделать", 1: "Сон", 8: "Выключить компьютер", 0: "Ничего" })
            last: !power.lidPresent
            label: "Кнопка питания"
            Choice {
                model: buttonRow.actions.map(a => buttonRow.names[a])
                currentIndex: buttonRow.actions.indexOf(power.powerButton)
                onActivated: index => power.setPowerButton(buttonRow.actions[index])
            }
        }
        Setting {
            id: lidRow
            visible: power.lidPresent
            readonly property var actions: power.canSuspend ? [1, 64, 0] : [64, 0]
            readonly property var names: ({ 1: "Сон", 64: "Выключить экран", 0: "Ничего" })
            last: true
            label: "Закрытие крышки"
            Choice {
                model: lidRow.actions.map(a => lidRow.names[a])
                currentIndex: lidRow.actions.indexOf(power.lidAction)
                onActivated: index => power.setLidAction(lidRow.actions[index])
            }
        }
    }

    SText {
        visible: power.error !== ""
        width: parent.width
        text: power.error
        color: Theme.terracotta
        wrapMode: Text.Wrap
    }

    SButton {
        text: "Батарея, яркость и другое…"
        onClicked: App.openKde("kcm_powerdevilprofilesconfig")
    }
}
