import QtQuick
import Sedmio.Store
import Sedmio.Style

// Установленное из AUR (под списком «Установленные» и в «Обновлениях»).
// onlyUpdates — только те, у которых в AUR новая версия.
Column {
    id: root
    property bool onlyUpdates: false
    signal open(string name)
    // «Посмотреть и обновить всё»: один просмотр на все обновления.
    signal reviewAll(var names)

    readonly property var all: Aur.installed.filter(p => p.inAur)
    readonly property var packages: onlyUpdates ? all.filter(p => p.update !== "") : all
    readonly property var batch: Jobs.list.length >= 0 ? Jobs.forApp("aur:@updates") : ({})
    readonly property bool batchRunning: batch.state === "waiting" || batch.state === "running"
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

    Item {
        width: parent.width
        height: Math.max(heading.implicitHeight, reviewAllButton.visible ? reviewAllButton.height : 0)
        SText {
            id: heading
            anchors.verticalCenter: parent.verticalCenter
            leftPadding: root.onlyUpdates ? 4 : 10
            text: "Из AUR"
            size: 13
            weight: 600
            color: Theme.inkSoft
        }
        SButton {
            id: reviewAllButton
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            visible: root.onlyUpdates && root.packages.length > 1 && !root.batchRunning
            primary: true
            text: "Посмотреть и обновить всё (" + root.packages.length + ")"
            onClicked: root.reviewAll(root.packages.map(p => p.name))
        }
    }
    // Идёт пакетное обновление.
    Column {
        visible: root.onlyUpdates && (root.batchRunning || root.batch.state === "failed")
        width: parent.width
        leftPadding: 4
        spacing: 6
        SText {
            width: parent.width - 4
            wrapMode: Text.Wrap
            size: 13
            color: root.batch.state === "failed" ? Theme.terracotta : Theme.inkSoft
            text: root.batch.state === "failed" ? (root.batch.error || "") : (root.batch.text || "")
        }
        JobLog {
            width: parent.width - 4
            job: root.batch
        }
        SButton {
            visible: root.batch.state === "failed"
            text: "Понятно"
            onClicked: Jobs.dismiss(root.batch.id)
        }
        SButton {
            visible: root.batch.cancellable === true
            text: "Отменить"
            onClicked: Jobs.cancel(root.batch.id)
        }
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
            badge: modelData.update === "новые коммиты" ? "новые коммиты" : modelData.update !== "" ? "есть " + modelData.update : ""
            side: modelData.update !== "" ? "Посмотреть и обновить ›" : ""
            onClicked: root.open(modelData.name)
        }
    }
}
