import QtQuick
import QtQuick.Controls
import Sedmio.Store
import Sedmio.Style

// Карточка программы: что это, снимки экрана, описание и откуда поставить.
Item {
    id: root
    property string appId
    readonly property var app: Catalog.ready && Catalog.revision >= 0 ? Catalog.details(appId) : ({})
    readonly property var sources: app.sources || []
    readonly property int contentWidth: Math.min(width - 64, 900)

    signal openUpdates()

    // Что будет при установке или удалении — для карточек источников.
    Preview { id: preview }
    // Перечитать, когда открыли другую программу или её поставили/удалили.
    readonly property string previewKey: (app.id || "") + "|" + (app.installed || "")
    onPreviewKeyChanged: if (app.id) preview.load(app)

    readonly property var job: Jobs.list.length >= 0 ? Jobs.forApp(appId) : ({})

    // Удалить? — спрашиваем, что уйдёт вместе.
    property string confirmKind

    // Снимок на весь экран (-1 — закрыт).
    property int viewing: -1

    Flickable {
        id: flick
        anchors.fill: parent
        contentHeight: column.height + 48
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
            id: column
            x: Math.max(32, (root.width - root.contentWidth) / 2)
            width: root.contentWidth
            topPadding: 24
            spacing: 24

            // Шапка.
            Item {
                width: parent.width
                height: Math.max(icon.height, head.height)
                AppIcon {
                    id: icon
                    source: root.app.icon || ""
                    size: 96
                }
                Column {
                    id: head
                    anchors { left: icon.right; leftMargin: 22; right: parent.right; verticalCenter: icon.verticalCenter }
                    spacing: 4
                    SText {
                        width: parent.width
                        text: root.app.name || ""
                        size: 28
                        weight: 680
                        wrapMode: Text.Wrap
                    }
                    SText {
                        visible: text !== ""
                        width: parent.width
                        text: root.app.developer || ""
                        color: Theme.inkMuted
                        elide: Text.ElideRight
                    }
                    SText {
                        width: parent.width
                        topPadding: 4
                        text: root.app.summary || ""
                        size: 15
                        color: Theme.inkSoft
                        wrapMode: Text.Wrap
                    }
                }
            }

            // Откуда поставить: равные карточки рядом (или одна).
            Column {
                width: parent.width
                spacing: 10
                SText {
                    visible: root.sources.length > 1 && root.app.installed === ""
                    text: "Есть в двух источниках — выберите, откуда поставить"
                    size: 13
                    weight: 600
                    color: Theme.inkSoft
                }
                Row {
                    id: sourceRow
                    width: parent.width
                    spacing: 12
                    Repeater {
                        id: sourceRepeater
                        model: root.sources
                        delegate: SourceCard {
                            required property var modelData
                            source: modelData
                            info: modelData.kind === "arch" ? preview.arch : preview.flathub
                            job: root.job.kind === modelData.kind ? root.job : ({})
                            width: root.sources.length > 1 ? (sourceRow.width - sourceRow.spacing) / 2 : Math.min(sourceRow.width, 460)
                            height: Math.max(implicitHeight, sourceRow.cardHeight)
                            onInstall: Jobs.install(root.app, modelData.kind)
                            onRemove: root.confirmKind = modelData.kind
                            onLaunch: Catalog.launch(root.appId, modelData.kind)
                            onCancel: Jobs.cancel(root.job.id)
                            onDismiss: Jobs.dismiss(root.job.id)
                            onOpenUpdates: root.openUpdates()
                        }
                    }
                    // Обе карточки — одной высоты.
                    readonly property real cardHeight: {
                        let h = 0;
                        for (let i = 0; i < sourceRepeater.count; i++) {
                            const card = sourceRepeater.itemAt(i);
                            if (card)
                                h = Math.max(h, card.implicitHeight);
                        }
                        return h;
                    }
                }
            }

            // Снимки экрана.
            ListView {
                id: shots
                visible: count > 0
                width: parent.width
                height: 300
                orientation: ListView.Horizontal
                spacing: 12
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: root.app.screenshots || []
                ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    readonly property real ratio: shot.status === Image.Ready && shot.implicitHeight > 0
                        ? shot.implicitWidth / shot.implicitHeight : 16 / 10
                    height: shots.height - 12
                    width: Math.min(height * ratio, shots.width)
                    radius: Theme.radius
                    color: Theme.paperDeep
                    border.width: 1
                    border.color: Theme.line
                    Image {
                        id: shot
                        anchors { fill: parent; margins: 1 }
                        source: parent.modelData.thumb
                        asynchronous: true
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        mipmap: true
                    }
                    BusyIndicator {
                        anchors.centerIn: parent
                        running: shot.status === Image.Loading
                        visible: running
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.viewing = parent.index
                    }
                }
            }

            // Описание.
            SText {
                visible: text !== ""
                width: parent.width
                text: root.app.description || ""
                textFormat: Text.StyledText
                wrapMode: Text.Wrap
                size: 14
                lineHeight: 1.25
                color: Theme.ink
            }

            Card {
                title: "Сведения"
                Info { label: "Разработчик"; value: root.app.developer || "" }
                Info { label: "Лицензия"; value: root.app.license || "" }
                Info { label: "Разделы"; value: (root.app.categories || []).join(", ") }
                Info {
                    label: "Сайт"
                    value: root.app.homepage || ""
                    link: true
                }
            }
        }
    }

    component Info: Item {
        property string label
        property string value
        property bool link: false
        visible: value !== ""
        width: parent ? parent.width : 0
        height: Math.max(40, valueText.implicitHeight + 20)
        SText {
            anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
            text: parent.label
            color: Theme.inkSoft
        }
        SText {
            id: valueText
            anchors { left: parent.left; leftMargin: 160; right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
            text: parent.value
            wrapMode: Text.WrapAnywhere
            color: parent.link ? Theme.green : Theme.ink
            MouseArea {
                anchors.fill: parent
                enabled: parent.parent.link
                cursorShape: Qt.PointingHandCursor
                onClicked: Qt.openUrlExternally(parent.text)
            }
        }
    }

    // Удалить?
    Rectangle {
        anchors.fill: parent
        visible: root.confirmKind !== ""
        color: Qt.alpha(Theme.ink, 0.25)
        onVisibleChanged: if (visible) { wipeData.checked = false; forceActiveFocus(); }
        Keys.onEscapePressed: root.confirmKind = ""
        MouseArea { anchors.fill: parent; onClicked: root.confirmKind = "" }

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width - 64, 440)
            height: confirmColumn.implicitHeight + 40
            radius: Theme.radius
            color: Theme.surface
            border.width: 1
            border.color: Theme.line
            MouseArea { anchors.fill: parent }

            Column {
                id: confirmColumn
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20 }
                spacing: 12
                SText {
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: "Удалить «" + (root.app.name || "") + "»?"
                    size: 18
                    weight: 650
                }
                SText {
                    width: parent.width
                    wrapMode: Text.Wrap
                    color: Theme.inkSoft
                    text: {
                        if (root.confirmKind === "arch") {
                            const removes = preview.arch.removes || [];
                            return removes.length > 0
                                ? "Вместе с ней уйдут пакеты, которые больше никому не нужны: " + removes.join(", ") + ". Ваши файлы останутся."
                                : "Ваши файлы останутся.";
                        }
                        return "Программа и среды выполнения, которые больше не нужны, будут удалены.";
                    }
                }
                Row {
                    visible: root.confirmKind === "flathub"
                    spacing: 10
                    Rectangle {
                        id: wipeData
                        property bool checked: false
                        anchors.verticalCenter: parent.verticalCenter
                        width: 20
                        height: 20
                        radius: 6
                        color: checked ? Theme.green : "transparent"
                        border.width: checked ? 0 : 1.5
                        border.color: Theme.inkMuted
                        SText {
                            anchors.centerIn: parent
                            visible: parent.checked
                            text: "✓"
                            size: 13
                            weight: 700
                            color: Theme.textOnGreen
                        }
                        MouseArea { anchors.fill: parent; onClicked: wipeData.checked = !wipeData.checked }
                    }
                    SText {
                        anchors.verticalCenter: parent.verticalCenter
                        width: confirmColumn.width - 30
                        wrapMode: Text.Wrap
                        text: "Удалить и её настройки и данные"
                        MouseArea { anchors.fill: parent; onClicked: wipeData.checked = !wipeData.checked }
                    }
                }
                Row {
                    anchors.right: parent.right
                    spacing: 8
                    topPadding: 4
                    SButton {
                        text: "Отмена"
                        onClicked: root.confirmKind = ""
                    }
                    SButton {
                        danger: true
                        text: "Удалить"
                        onClicked: {
                            Jobs.remove(root.app, root.confirmKind, wipeData.checked);
                            root.confirmKind = "";
                        }
                    }
                }
            }
        }
    }

    // Снимок крупно: ← → листают, Esc или щелчок — закрыть.
    Rectangle {
        anchors.fill: parent
        visible: root.viewing >= 0
        color: Qt.alpha("black", 0.82)
        focus: visible
        onVisibleChanged: if (visible) forceActiveFocus()
        Keys.onEscapePressed: root.viewing = -1
        Keys.onLeftPressed: if (root.viewing > 0) root.viewing--
        Keys.onRightPressed: if (root.viewing < shots.count - 1) root.viewing++
        MouseArea {
            anchors.fill: parent
            onClicked: root.viewing = -1
        }
        Image {
            id: big
            anchors { fill: parent; margins: 40 }
            source: root.viewing >= 0 ? root.app.screenshots[root.viewing].full : ""
            asynchronous: true
            fillMode: Image.PreserveAspectFit
            smooth: true
            mipmap: true
        }
        BusyIndicator {
            anchors.centerIn: parent
            running: big.status === Image.Loading
            visible: running
        }
    }
}
