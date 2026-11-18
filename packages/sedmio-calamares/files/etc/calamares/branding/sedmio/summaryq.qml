import QtQuick
import io.calamares.core 1.0
import io.calamares.ui 1.0
import "components"

// Итог перед установкой: что получится, простыми словами.
// Calamares даёт сводку модулей (config.summaryModel: title, message) —
// это технический список шагов («Создается новая GPT таблица…»). Из него
// и из общего хранилища (Global) собираем три понятных блока: время и язык,
// пользователь, диск. Шаги разметки целиком — под «Подробнее».
SPage {
    id: page

    stage: 5
    centerVertically: false

    property var rows: []

    function onActivate() {
        page.rows = page.buildRows()
        page.replayAppear()
    }

    // Сводку Calamares собирает при входе на страницу (сбросом модели) —
    // порядок относительно onActivate не гарантирован, поэтому слушаем и его
    Connections {
        target: config.summaryModel
        function onModelReset() { page.rows = page.buildRows() }
    }

    // Убрать разметку Calamares: <strong>, <em>, <br/> и т. п.
    function plain(html) {
        return (html || "").replace(/<br\s*\/?>/gi, "\n")
                           .replace(/<\/?[a-z][^>]*>/gi, "")
                           .replace(/&lt;/g, "<").replace(/&gt;/g, ">")
                           .replace(/&quot;/g, "\"").replace(/&amp;/g, "&")
                           .replace(/…/g, "").replace(/\.\.\.$/gm, "")
                           .trim()
    }

    // «Азия/Бангкок» → «Бангкок, Азия» (как на странице выбора часового пояса)
    function placeName(name) {
        const parts = (name || "").split("/")
        return parts.length === 2 ? parts[1] + ", " + parts[0] : name
    }

    function timeText(message) {
        // Русское название пояса есть только в тексте сводки модуля:
        // «Часовой пояс изменен на Азия/Бангкок.» В хранилище — английское.
        const m = plain(message).match(/на ([^.\n]+\/[^.\n]+)\./)
        let zone = m ? placeName(m[1]) : ""
        if (zone === "") {
            const z = String(Global.value("locationZone") || "").replace(/_/g, " ")
            const r = String(Global.value("locationRegion") || "")
            zone = z !== "" ? z + (r !== "" ? ", " + r : "") : ""
        }
        return (zone !== "" ? "Часовой пояс — " + zone + ". " : "")
               + "Язык и форматы — русские."
    }

    function userText() {
        const name = String(Global.value("fullname") || "")
        const login = String(Global.value("username") || "")
        const host = String(Global.value("hostname") || "")
        const auto = String(Global.value("autoLoginUser") || "") !== ""
        let t = name !== "" ? name : login
        if (login !== "" && login !== name)
            t += " (логин " + login + ")"
        t += ". " + (auto ? "Рабочий стол откроется без пароля."
                          : "Вход в систему — по паролю.")
        if (host !== "")
            t += " Имя компьютера — " + host + "."
        return t
    }

    function diskText(message) {
        const text = plain(message)
        const dev = (text.match(/\/dev\/[A-Za-z0-9]+/) || [""])[0]
        const fs = /btrfs/i.test(text) ? "btrfs" : /ext4/i.test(text) ? "ext4" : ""
        const erase = /Очистить|Erase/i.test(text)
        const crypt = /LUKS|шифр|encrypt/i.test(text)
        let t
        if (erase) {
            t = "Диск " + dev + " будет полностью стёрт. На нём появятся загрузочный раздел "
                + "и раздел для системы" + (fs !== "" ? " (" + fs + ")" : "") + "."
        } else if (dev !== "") {
            t = "Sedmio установится на диск " + dev + " так, как вы его разметили."
        } else {
            t = "Sedmio установится так, как вы разметили диск."
        }
        if (crypt)
            t += " Система будет зашифрована: пароль понадобится при каждом включении."
        return t
    }

    function buildRows() {
        const model = config.summaryModel
        const out = []
        let user = false
        for (let i = 0; i < model.rowCount(); ++i) {
            // Роли SummaryModel: title — DisplayRole, message — UserRole
            const title = model.data(model.index(i, 0), Qt.DisplayRole) || ""
            const message = model.data(model.index(i, 0), Qt.UserRole) || ""
            const text = plain(message)
            if (/\/dev\//.test(text)) {
                // Пользователь — перед диском: так короче путь до главного
                if (!user) {
                    out.push({ title: "Пользователь", text: userText(), details: "" })
                    user = true
                }
                out.push({ title: "Диск", text: diskText(message),
                           details: text.split("\n").map(s => s.trim()).filter(s => s !== "").join("\n") })
            } else if (/Часовой пояс|timezone/i.test(text)) {
                out.push({ title: "Время и язык", text: timeText(message), details: "" })
            } else if (text !== "") {
                out.push({ title: title, text: text, details: "" })
            }
        }
        if (!user)
            out.splice(Math.min(1, out.length), 0, { title: "Пользователь", text: userText(), details: "" })
        return out
    }

    PageHeader {
        width: parent.width
        eyebrow: "Почти готово"
        title: "Проверим всё ещё раз"
    }

    Column {
        width: parent.width
        spacing: 0

        Repeater {
            model: page.rows

            delegate: Column {
                id: row
                width: parent.width
                spacing: 5
                bottomPadding: 12

                property bool open: false

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Theme.line
                    visible: index > 0
                }
                Item { width: 1; height: index > 0 ? 6 : 0 }

                Text {
                    width: parent.width
                    text: modelData.title
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSmall
                    font.weight: Font.DemiBold
                    font.letterSpacing: 0.8
                    font.capitalization: Font.AllUppercase
                    color: Theme.inkMuted
                }
                Text {
                    width: parent.width
                    text: modelData.text
                    wrapMode: Text.WordWrap
                    lineHeight: 1.25
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontBody
                    color: Theme.ink
                }

                // «Подробнее»: шаги разметки так, как их выполнит установщик
                Item {
                    visible: modelData.details !== ""
                    width: moreRow.implicitWidth
                    height: moreRow.implicitHeight + 2

                    Row {
                        id: moreRow
                        y: 2
                        spacing: 6
                        Text {
                            id: moreLabel
                            text: row.open ? "Скрыть подробности" : "Подробнее"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSmall
                            font.weight: Font.Medium
                            color: moreMouse.containsMouse ? Theme.greenHover : Theme.green
                        }
                        Text {
                            anchors.verticalCenter: moreLabel.verticalCenter
                            text: "›"
                            rotation: row.open ? 90 : 0
                            font.pixelSize: Theme.fontBody
                            color: moreLabel.color
                            Behavior on rotation { SpringAnimation { spring: 4; damping: 0.3 } }
                        }
                    }
                    MouseArea {
                        id: moreMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: row.open = !row.open
                    }
                }

                Text {
                    visible: row.open
                    width: parent.width
                    text: modelData.details
                    wrapMode: Text.WordWrap
                    lineHeight: 1.3
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSmall
                    color: Theme.inkSoft
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
