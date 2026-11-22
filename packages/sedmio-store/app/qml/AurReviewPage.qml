import QtQuick
import QtQuick.Controls
import Sedmio.Store
import Sedmio.Style

// Просмотр пакетов AUR перед сборкой: сами пакеты и их зависимости из
// AUR, все файлы каждого и что автопроверка советует посмотреть. Собрать
// можно, только отметив каждый пакет просмотренным; соберётся ровно то,
// что здесь показано (AurReview запоминает отпечаток).
Item {
    id: root
    property var targets: []
    property bool update: false
    signal done()

    property string selected: ""       // base
    property string file: "PKGBUILD"

    readonly property var packages: review.packages
    readonly property var current: packages.find(p => p.base === selected) || ({})
    readonly property int dangerTotal: packages.reduce((n, p) => n + p.danger, 0)

    AurReview {
        id: review
        onStateChanged: if (state === "ready" && root.packages.length > 0) root.select(root.packages[0].base)
    }
    Component.onCompleted: review.start(targets)

    function select(base) {
        selected = base;
        file = "PKGBUILD";
    }
    function sizeText(bytes) {
        if (bytes >= 1024 * 1024 * 1024) return (bytes / 1024 / 1024 / 1024).toFixed(1).replace(".", ",") + " ГБ";
        if (bytes >= 1024 * 1024) return Math.round(bytes / 1024 / 1024) + " МБ";
        return Math.max(1, Math.round(bytes / 1024)) + " КБ";
    }
    function levelColor(level) {
        return level === "danger" ? Theme.terracotta : level === "check" ? Theme.warning : Theme.inkMuted;
    }
    // Отметить и перейти к следующему непросмотренному.
    function markReviewed() {
        review.setReviewed(selected, true);
        const next = packages.find(p => !p.reviewed && p.base !== selected);
        if (next)
            select(next.base);
    }

    // ---- Загрузка и ошибка
    Column {
        visible: review.state !== "ready"
        anchors.centerIn: parent
        width: Math.min(parent.width - 64, 520)
        spacing: 14
        BusyIndicator {
            visible: review.state === "loading"
            anchors.horizontalCenter: parent.horizontalCenter
            running: visible
        }
        SText {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            color: review.state === "failed" ? Theme.terracotta : Theme.inkSoft
            text: review.state === "failed" ? review.error : review.status
        }
        SButton {
            visible: review.state === "failed"
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Попробовать ещё раз"
            onClicked: review.start(root.targets)
        }
    }

    // ---- Просмотр
    Item {
        visible: review.state === "ready"
        anchors.fill: parent

        Column {
            id: head
            anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 32; rightMargin: 32; topMargin: 20 }
            spacing: 4
            SText {
                text: root.update ? "Просмотр перед обновлением" : "Просмотр перед сборкой"
                size: 24
                weight: 650
            }
            SText {
                width: parent.width
                wrapMode: Text.Wrap
                color: Theme.inkSoft
                text: "Пакеты AUR никто не проверяет. Посмотрите каждый: откуда скачиваются исходники и что делается при сборке и установке. "
                    + "Соберётся ровно то, что здесь показано."
            }
        }

        // Список пакетов.
        ListView {
            id: list
            anchors { left: parent.left; top: head.bottom; bottom: footer.top; leftMargin: 24; topMargin: 16; bottomMargin: 12 }
            width: 250
            clip: true
            spacing: 6
            model: root.packages
            boundsBehavior: Flickable.StopAtBounds
            delegate: Rectangle {
                id: item
                required property var modelData
                width: ListView.view.width
                height: itemColumn.implicitHeight + 20
                radius: Theme.radius
                color: root.selected === modelData.base ? Theme.greenWash : itemArea.containsMouse ? Theme.paperDeep : Theme.surface
                border.width: 1
                border.color: Theme.line
                Column {
                    id: itemColumn
                    anchors { left: parent.left; right: mark.left; leftMargin: 12; rightMargin: 6; verticalCenter: parent.verticalCenter }
                    spacing: 3
                    SText {
                        width: parent.width
                        elide: Text.ElideRight
                        text: item.modelData.base
                        weight: 600
                    }
                    SText {
                        width: parent.width
                        elide: Text.ElideRight
                        size: 12
                        color: Theme.inkMuted
                        text: (item.modelData.target ? "" : "зависимость · ") + item.modelData.version
                    }
                    Row {
                        spacing: 8
                        visible: item.modelData.danger + item.modelData.check > 0
                        SText {
                            visible: item.modelData.danger > 0
                            text: "опасное: " + item.modelData.danger
                            size: 12
                            weight: 600
                            color: Theme.terracotta
                        }
                        SText {
                            visible: item.modelData.check > 0
                            text: "проверить: " + item.modelData.check
                            size: 12
                            weight: 600
                            color: Theme.warning
                        }
                    }
                }
                SIcon {
                    id: mark
                    anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    name: item.modelData.reviewed ? "checkmark" : ""
                    size: 16
                    visible: item.modelData.reviewed
                }
                MouseArea {
                    id: itemArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.select(item.modelData.base)
                }
            }
        }

        // Выбранный пакет.
        Item {
            id: detail
            anchors { left: list.right; right: parent.right; top: head.bottom; bottom: footer.top; leftMargin: 16; rightMargin: 24; topMargin: 16; bottomMargin: 12 }

            Column {
                id: info
                width: parent.width
                spacing: 8

                SText {
                    width: parent.width
                    wrapMode: Text.Wrap
                    size: 13
                    color: Theme.inkSoft
                    text: {
                        const p = root.current;
                        if (p.base === undefined) return "";
                        let parts = [p.summary || ""];
                        parts.push("сопровождает " + (p.maintainer || "никто"));
                        parts.push("голосов " + p.votes);
                        if (p.submitted) parts.push("в AUR с " + p.submitted);
                        if (p.installed) parts.push("сейчас стоит " + p.installed);
                        return parts.filter(s => s !== "").join(" · ");
                    }
                }

                // Находки автопроверки.
                Rectangle {
                    width: parent.width
                    height: Math.min(findings.implicitHeight + 20, 190)
                    radius: Theme.radius
                    color: Theme.surface
                    border.width: 1
                    border.color: (root.current.danger || 0) > 0 ? Theme.terracotta : Theme.line
                    Flickable {
                        anchors { fill: parent; margins: 10 }
                        contentHeight: findings.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                        Column {
                            id: findings
                            width: parent.width
                            spacing: 6
                            SText {
                                visible: (root.current.findings || []).length === 0
                                width: parent.width
                                wrapMode: Text.Wrap
                                size: 13
                                color: Theme.inkSoft
                                text: "Автопроверка ничего не нашла. Это не значит, что пакет безопасен: она знает только частые приёмы."
                            }
                            Repeater {
                                model: root.current.findings || []
                                delegate: Row {
                                    id: finding
                                    required property var modelData
                                    width: findings.width
                                    spacing: 8
                                    Rectangle {
                                        y: 6
                                        width: 8
                                        height: 8
                                        radius: 4
                                        color: root.levelColor(finding.modelData.level)
                                    }
                                    SText {
                                        width: parent.width - 16
                                        wrapMode: Text.Wrap
                                        size: 13
                                        color: finding.modelData.level === "note" ? Theme.inkSoft : Theme.ink
                                        textFormat: Text.StyledText
                                        text: finding.modelData.message
                                            + (finding.modelData.file !== "" && finding.modelData.line > 0
                                               ? " — <a href=\"#\">" + finding.modelData.file + ":" + finding.modelData.line + "</a>" : "")
                                        linkColor: Theme.green
                                        onLinkActivated: {
                                            root.file = finding.modelData.file;
                                            Qt.callLater(() => code.show(finding.modelData.line));
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Файлы пакета.
                Flow {
                    width: parent.width
                    spacing: 6
                    Repeater {
                        model: root.current.files || []
                        delegate: Rectangle {
                            id: tab
                            required property var modelData
                            readonly property bool active: root.file === modelData.name
                            width: tabText.implicitWidth + 20
                            height: 28
                            radius: 14
                            color: active ? Theme.green : Theme.surface
                            border.width: active ? 0 : 1
                            border.color: Theme.line
                            opacity: modelData.binary ? 0.55 : 1
                            SText {
                                id: tabText
                                anchors.centerIn: parent
                                text: tab.modelData.name + (tab.modelData.binary ? " (не текст, " + root.sizeText(tab.modelData.size) + ")" : "")
                                size: 12
                                weight: 600
                                color: tab.active ? Theme.textOnGreen : Theme.ink
                            }
                            MouseArea {
                                anchors.fill: parent
                                enabled: !tab.modelData.binary
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.file = tab.modelData.name
                            }
                        }
                    }
                }
            }

            // Текст файла с номерами строк; строки с находками подсвечены.
            Rectangle {
                anchors { left: parent.left; right: parent.right; top: info.bottom; bottom: reviewedRow.top; topMargin: 8; bottomMargin: 10 }
                radius: Theme.radius
                color: Theme.paperDeep
                border.width: 1
                border.color: Theme.line

                ListView {
                    id: code
                    anchors { fill: parent; margins: 8 }
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    flickableDirection: Flickable.AutoFlickIfNeeded
                    contentWidth: Math.max(width, widest * glyph.advanceWidth + 60)
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }

                    readonly property var lines: root.selected !== "" && review.state === "ready" ? review.fileText(root.selected, root.file).split("\n") : []
                    readonly property int widest: lines.reduce((n, l) => Math.max(n, l.length), 0)
                    readonly property var marks: {
                        const m = {};
                        for (const f of (root.current.findings || []))
                            if (f.file === root.file && f.line > 0 && (m[f.line] === undefined || f.level === "danger"))
                                m[f.line] = f.level;
                        return m;
                    }
                    property int flash: 0
                    function show(line) {
                        positionViewAtIndex(Math.max(0, line - 1), ListView.Center);
                        flash = line;
                    }
                    onLinesChanged: positionViewAtBeginning()
                    model: lines.length

                    TextMetrics {
                        id: glyph
                        font.family: "monospace"
                        font.pixelSize: 12
                        text: "M"
                    }

                    delegate: Rectangle {
                        id: lineItem
                        required property int index
                        readonly property string level: code.marks[index + 1] || ""
                        width: code.contentWidth
                        height: 18
                        color: level === "danger" ? Theme.terracottaSoft
                            : level === "check" ? Qt.rgba(Theme.warning.r, Theme.warning.g, Theme.warning.b, 0.18)
                            : level === "note" ? Qt.rgba(Theme.inkMuted.r, Theme.inkMuted.g, Theme.inkMuted.b, 0.12)
                            : code.flash === index + 1 ? Theme.greenWash : "transparent"
                        Text {
                            width: 40
                            horizontalAlignment: Text.AlignRight
                            anchors.verticalCenter: parent.verticalCenter
                            text: lineItem.index + 1
                            font.family: "monospace"
                            font.pixelSize: 12
                            color: Theme.inkMuted
                        }
                        Text {
                            x: 52
                            anchors.verticalCenter: parent.verticalCenter
                            text: code.lines[lineItem.index]
                            textFormat: Text.PlainText
                            font.family: "monospace"
                            font.pixelSize: 12
                            color: Theme.ink
                        }
                    }
                }
            }

            Row {
                id: reviewedRow
                anchors { left: parent.left; bottom: parent.bottom }
                spacing: 10
                SButton {
                    visible: root.current.reviewed === false
                    primary: (root.current.danger || 0) === 0
                    text: "Просмотрено"
                    onClicked: root.markReviewed()
                }
                SButton {
                    visible: root.current.reviewed === true
                    text: "Снять отметку"
                    onClicked: review.setReviewed(root.selected, false)
                }
                SText {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.current.reviewed === true
                    text: "Пакет отмечен просмотренным"
                    color: Theme.inkSoft
                }
            }
        }

        // Итог и сборка.
        Rectangle {
            id: footer
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: footerRow.implicitHeight + 28
            color: Theme.surface
            Rectangle {
                anchors { left: parent.left; right: parent.right; top: parent.top }
                height: 1
                color: Theme.line
            }
            Row {
                id: footerRow
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 32; rightMargin: 32 }
                spacing: 16
                SText {
                    width: parent.width - buildButton.width - parent.spacing
                    anchors.verticalCenter: parent.verticalCenter
                    wrapMode: Text.Wrap
                    size: 13
                    color: root.dangerTotal > 0 && review.allReviewed ? Theme.terracotta : Theme.inkSoft
                    text: {
                        const left = root.packages.filter(p => !p.reviewed).length;
                        let parts = [];
                        if (left > 0)
                            parts.push("Осталось посмотреть: " + left + " из " + root.packages.length);
                        else if (root.dangerTotal > 0)
                            parts.push("Автопроверка нашла опасное. Собирайте, только если точно понимаете, зачем это пакету");
                        if (review.repoDeps.length > 0)
                            parts.push("из репозиториев поставится " + review.repoDeps.join(", ")
                                       + (review.repoDownload > 0 ? " (скачать " + root.sizeText(review.repoDownload) + ")" : ""));
                        const s = parts.join("; ");
                        return s.charAt(0).toUpperCase() + s.slice(1);
                    }
                }
                SButton {
                    id: buildButton
                    anchors.verticalCenter: parent.verticalCenter
                    enabled: review.allReviewed
                    opacity: enabled ? 1 : 0.5
                    primary: root.dangerTotal === 0
                    danger: root.dangerTotal > 0
                    text: (root.update ? "Собрать и обновить" : "Собрать и установить")
                        + (root.packages.length > 1 ? " (" + root.packages.length + ")" : "")
                    onClicked: {
                        if (!review.allReviewed)
                            return;
                        Jobs.buildAur(review.plan(), root.update ? "update" : "install");
                        root.done();
                    }
                }
            }
        }
    }
}
