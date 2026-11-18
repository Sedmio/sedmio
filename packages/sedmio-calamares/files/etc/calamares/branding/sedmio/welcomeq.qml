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

    // Свои тексты проверок: переводы Calamares звучат машинно
    // («имеет как малость один доступный накопитель»). Числа — как в
    // modules/welcomeq.conf, менять вместе. Неизвестные проверки
    // показываются текстом Calamares.
    function describe(name, ok, fallback) {
        const texts = {
            "storage":    ["На диске есть не меньше 30 ГиБ свободного места",
                           "На диске меньше 30 ГиБ свободного места"],
            "partitions": ["Есть диск, на который можно установить систему",
                           "Не найден диск, на который можно установить систему"],
            "ram":        ["Оперативной памяти не меньше 4 ГиБ",
                           "Оперативной памяти меньше 4 ГиБ"],
            "power":      ["Компьютер подключён к сети питания",
                           "Компьютер не подключён к сети питания — лучше подключить"],
            "internet":   ["Есть подключение к интернету",
                           "Нет подключения к интернету — оно нужно для установки"],
            "root":       ["Установщик запущен с правами администратора",
                           "Установщик запущен без прав администратора"],
            "screen":     ["Экран достаточно большой",
                           "Экран слишком маленький для установщика"]
        }
        if (texts[name]) return texts[name][ok ? 0 : 1]
        return fallback.charAt(0).toUpperCase() + fallback.slice(1)
    }

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

        // Всё хорошо — одна строка, а не список из зелёных галочек
        Message {
            width: parent.width
            visible: page.req.satisfiedRequirements
            kind: "ok"
            text: "Компьютер подходит для установки Sedmio"
        }

        // Иначе — только то, что не прошло. Полная модель (page.req)
        // заполняется из потока проверки, и Repeater на ней оставался пустым.
        Repeater {
            id: checks
            model: config.unsatisfiedRequirements
            delegate: Message {
                width: parent.width
                kind: model.mandatory ? "error" : "warning"
                text: page.describe(model.name, false, model.negatedText)
            }
        }

        Text {
            visible: !page.req.satisfiedRequirements && checks.count === 0
            width: parent.width
            text: "Проверяем компьютер…"
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
