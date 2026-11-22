import QtQuick
import Sedmio.Store
import Sedmio.Style

// Под результатами поиска: пакеты репозиториев без карточки в каталоге —
// консольные программы, шрифты, дополнения (htop, ffmpeg, ttf-…).
Column {
    id: root
    property string query
    property bool expanded: false
    signal open(string id)

    readonly property var packages: Catalog.ready && Catalog.revision >= 0 ? Catalog.searchPackages(query, 60) : []
    readonly property var shown: expanded ? packages : packages.slice(0, 6)
    onQueryChanged: expanded = false

    visible: packages.length > 0
    topPadding: 18
    spacing: 8

    SText {
        leftPadding: 10
        text: "Пакеты"
        size: 13
        weight: 600
        color: Theme.inkSoft
    }
    Repeater {
        model: root.shown
        delegate: AurRow {
            required property var modelData
            name: modelData.name
            version: modelData.version
            summary: modelData.summary
            badge: modelData.installed ? "установлен" : ""
            side: modelData.repo
            onClicked: root.open(modelData.id)
        }
    }
    SText {
        visible: !root.expanded && root.packages.length > root.shown.length
        leftPadding: 10
        text: "Показать ещё " + (root.packages.length - root.shown.length)
        size: 13
        weight: 600
        color: Theme.green
        MouseArea {
            anchors.fill: parent
            anchors.margins: -4
            cursorShape: Qt.PointingHandCursor
            onClicked: root.expanded = true
        }
    }
}
