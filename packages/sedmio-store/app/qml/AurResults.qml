import QtQuick
import Sedmio.Store
import Sedmio.Style

// Под результатами поиска: AUR — только по кнопке (не на каждую букву:
// так Pamac когда-то положил сервер AUR). Результаты — строками.
Column {
    id: root
    property string query
    signal open(string name)

    readonly property bool shown: Aur.query === query.trim().toLowerCase() && query.trim() !== ""
    topPadding: 18
    bottomPadding: 32
    spacing: 10

    Rectangle {
        x: 6
        width: root.width - 12
        height: offer.implicitHeight + 28
        radius: Theme.radius
        color: Theme.surface
        border.width: 1
        border.color: Theme.line
        Row {
            id: offer
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 16; rightMargin: 16 }
            spacing: 14
            Column {
                width: parent.width - searchButton.width - parent.spacing
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                SText {
                    text: "AUR — пакеты от пользователей Arch"
                    weight: 600
                }
                SText {
                    width: parent.width
                    wrapMode: Text.Wrap
                    size: 13
                    color: Theme.inkSoft
                    text: Aur.searching && root.shown ? "Ищу…"
                        : root.shown && Aur.error !== "" ? Aur.error
                        : root.shown ? "Найдено: " + Aur.results.length + ". Их никто не проверяет — перед сборкой покажем PKGBUILD."
                        : "Их никто не проверяет, и ставятся они сборкой на этом компьютере. Искать там, если здесь нужного нет."
                }
            }
            SButton {
                id: searchButton
                anchors.verticalCenter: parent.verticalCenter
                visible: !root.shown || Aur.error !== ""
                text: "Искать в AUR"
                onClicked: Aur.search(root.query)
            }
        }
    }

    Repeater {
        model: root.shown ? Aur.results : []
        delegate: AurRow {
            required property var modelData
            name: modelData.name
            version: modelData.version
            summary: modelData.summary
            badge: modelData.installed !== "" ? "установлен" : modelData.outOfDate ? "устарел" : ""
            badgeColor: modelData.installed !== "" ? Theme.green : Theme.terracotta
            side: "★ " + modelData.votes
            onClicked: root.open(modelData.name)
        }
    }
}
