import QtQuick
import Sedmio.Store
import Sedmio.Style

// Установленное из AUR (под списком «Установленные» и в «Обновлениях»).
// onlyUpdates — только те, у которых в AUR новая версия.
Column {
    id: root
    property bool onlyUpdates: false
    signal open(string name)

    readonly property var all: Aur.installed.filter(p => p.inAur)
    readonly property var packages: onlyUpdates ? all.filter(p => p.update !== "") : all
    // Из AUR ничего не стоит — блока нет.
    visible: all.length > 0
    Component.onCompleted: Aur.checkUpdates()
    Connections {
        target: Jobs
        function onFinished(appId) {
            if (appId.startsWith("aur:")) Aur.checkUpdates();
        }
    }

    topPadding: 18
    bottomPadding: 32
    spacing: 10

    SText {
        leftPadding: root.onlyUpdates ? 4 : 10
        text: "Из AUR"
        size: 13
        weight: 600
        color: Theme.inkSoft
    }
    SText {
        visible: root.onlyUpdates && root.packages.length === 0
        leftPadding: 4
        color: Theme.inkSoft
        text: Aur.checking ? "Проверяю…" : "Всё обновлено"
    }
    Repeater {
        model: root.packages
        delegate: AurRow {
            required property var modelData
            inset: root.onlyUpdates ? 0 : 6
            name: modelData.name
            version: modelData.version
            badge: modelData.update !== "" ? "есть " + modelData.update : ""
            side: modelData.update !== "" ? "Посмотреть и обновить ›" : ""
            onClicked: root.open(modelData.name)
        }
    }
}
