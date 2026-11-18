import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Sedmio.Files

// Вопросы заданий: «здесь уже есть такой файл», «не получилось —
// пропустить?», «чем открыть?». Одно окно на программу, над тем окном
// «Файлов», где работали последним. Что спросить — Prompts.current.
Window {
    id: win
    readonly property var q: Prompts.current
    readonly property string kind: q.kind ?? ""

    function reply(answer) { Prompts.answer(answer); }

    title: kind === "openWith" ? "Открыть с помощью" : "Файлы"
    flags: Qt.Dialog
    modality: Qt.WindowModal
    transientParent: Prompts.parentWindow
    visible: kind !== ""
    color: Theme.paper

    // Размер по содержимому, растягивать незачем.
    readonly property int contentWidth: loader.item ? loader.item.implicitWidth : 480
    readonly property int contentHeight: loader.item ? loader.item.implicitHeight : 200
    width: contentWidth
    height: contentHeight
    minimumWidth: contentWidth
    maximumWidth: contentWidth
    minimumHeight: contentHeight
    maximumHeight: contentHeight

    // Закрыли крестиком — как «Отмена».
    onClosing: close => {
        close.accepted = false;
        reply({ choice: "cancel" });
    }

    Loader {
        id: loader
        anchors.fill: parent
        focus: true
        sourceComponent: win.kind === "conflict" ? conflictView
            : win.kind === "skip" ? skipView
            : win.kind === "openWith" ? openWithView
            : null
    }

    // ---- Здесь уже есть такой файл

    Component {
        id: conflictView

        FocusScope {
            id: view
            readonly property var src: win.q.source
            readonly property var dst: win.q.dest
            readonly property bool newer: src.modified > dst.modified
            readonly property bool older: src.modified < dst.modified

            implicitWidth: 600
            implicitHeight: column.implicitHeight + 48
            focus: true

            function choose(choice) {
                win.reply({ choice: choice, all: forAll.checked, name: nameField.text });
            }
            Keys.onEscapePressed: choose("cancel")
            Keys.onReturnPressed: choose(win.q.canReplace ? "replace" : win.q.canRename ? "rename" : "skip")

            ColumnLayout {
                id: column
                anchors { fill: parent; margins: 24 }
                spacing: 14

                ColumnLayout {
                    spacing: 4
                    SText {
                        Layout.fillWidth: true
                        size: 18
                        weight: 650
                        wrapMode: Text.Wrap
                        text: win.q.itself ? "«" + view.dst.name + "» копируется сам в себя"
                            : win.q.merge ? "Здесь уже есть папка «" + view.dst.name + "»"
                            : "Здесь уже есть «" + view.dst.name + "»"
                    }
                    SText {
                        Layout.fillWidth: true
                        color: Theme.inkSoft
                        wrapMode: Text.Wrap
                        text: win.q.itself ? "Можно сохранить копию под другим именем."
                            : win.q.merge ? "Если объединить, файлы из новой папки лягут в эту; одинаковые — спрошу отдельно."
                            : "В папке " + FileOps.prettyPath(view.dst.folder) + ". Что сделать с новым?"
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    visible: !win.q.itself

                    FileCard {
                        Layout.fillWidth: true
                        label: "Уже здесь"
                        file: view.dst
                        mark: view.older ? "новее" : ""
                    }
                    FileCard {
                        Layout.fillWidth: true
                        label: "Новый"
                        file: view.src
                        mark: view.newer ? "новее" : ""
                    }
                }

                // Под каким именем сохранить, если «Оставить оба»
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    visible: win.q.canRename && !forAll.checked
                    SText {
                        text: "Новое имя"
                        color: Theme.inkSoft
                    }
                    Field {
                        id: nameField
                        Layout.fillWidth: true
                        text: win.q.suggestedName ?? ""
                    }
                }

                Check {
                    id: forAll
                    visible: win.q.multiple
                    text: "Так же со всеми остальными совпадениями"
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    spacing: 8

                    SButton {
                        text: "Отмена"
                        onClicked: view.choose("cancel")
                    }
                    Item { Layout.fillWidth: true }
                    SButton {
                        visible: win.q.canSkip
                        text: "Пропустить"
                        onClicked: view.choose("skip")
                    }
                    SButton {
                        visible: win.q.canRename
                        primary: !win.q.canReplace
                        text: "Оставить оба"
                        onClicked: view.choose("rename")
                    }
                    SButton {
                        visible: win.q.canReplace
                        primary: true
                        text: win.q.merge ? "Объединить" : "Заменить"
                        onClicked: view.choose("replace")
                    }
                }
            }
        }
    }

    // ---- Не получилось с одним из файлов

    Component {
        id: skipView

        FocusScope {
            id: view
            implicitWidth: 520
            implicitHeight: column.implicitHeight + 48
            focus: true

            function choose(choice) { win.reply({ choice: choice, all: forAll.checked }); }
            Keys.onEscapePressed: choose("cancel")
            Keys.onReturnPressed: choose("skip")

            ColumnLayout {
                id: column
                anchors { fill: parent; margins: 24 }
                spacing: 12

                SText {
                    Layout.fillWidth: true
                    size: 18
                    weight: 650
                    text: "Не получилось"
                }
                SText {
                    Layout.fillWidth: true
                    color: Theme.inkSoft
                    wrapMode: Text.Wrap
                    text: win.q.text ?? ""
                }
                Check {
                    id: forAll
                    visible: win.q.multiple
                    text: "Пропускать и другие такие ошибки"
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    spacing: 8
                    SButton {
                        text: "Остановить"
                        onClicked: view.choose("cancel")
                    }
                    Item { Layout.fillWidth: true }
                    SButton {
                        visible: win.q.canReplaceChars
                        text: "Заменить символы"
                        onClicked: view.choose("replaceChars")
                    }
                    SButton {
                        visible: win.q.canRetry
                        text: "Повторить"
                        onClicked: view.choose("retry")
                    }
                    SButton {
                        primary: true
                        text: "Пропустить"
                        onClicked: view.choose("skip")
                    }
                }
            }
        }
    }

    // ---- Чем открыть

    Component {
        id: openWithView

        FocusScope {
            id: view
            implicitWidth: 520
            implicitHeight: 600
            focus: true

            readonly property var suggested: win.q.apps ?? []
            readonly property var all: Prompts.allApplications()
            property string selected: suggested.length > 0 ? suggested[0].id : ""

            // Подходящие сверху, потом все остальные; при поиске — всё, что совпало.
            readonly property var rows: {
                const text = search.text.trim().toLowerCase();
                const match = app => text === "" || app.name.toLowerCase().includes(text)
                    || (app.comment ?? "").toLowerCase().includes(text);
                const ids = new Set(suggested.map(a => a.id));
                const top = suggested.filter(match).map(a => Object.assign({ section: "Подходят" }, a));
                const rest = all.filter(a => !ids.has(a.id) && match(a))
                    .map(a => Object.assign({ section: "Все программы" }, a));
                return top.concat(rest);
            }
            onRowsChanged: if (rows.length > 0 && !rows.some(r => r.id === selected)) selected = rows[0].id

            function open() {
                if (selected !== "") win.reply({ id: selected, remember: remember.checked });
            }
            Keys.onEscapePressed: win.reply({ id: "" })

            ColumnLayout {
                anchors { fill: parent; margins: 24 }
                spacing: 12

                ColumnLayout {
                    spacing: 4
                    SText {
                        Layout.fillWidth: true
                        size: 18
                        weight: 650
                        elide: Text.ElideMiddle
                        text: win.q.count > 1 ? "Чем открыть " + Format.items(win.q.count) + "?"
                                              : "Чем открыть «" + (win.q.name ?? "") + "»?"
                    }
                    SText {
                        Layout.fillWidth: true
                        visible: text !== ""
                        color: Theme.inkSoft
                        text: win.q.typeName ?? ""
                    }
                }

                Field {
                    id: search
                    Layout.fillWidth: true
                    focus: true
                    placeholderText: "Найти программу"
                    Keys.onReturnPressed: view.open()
                    Keys.onDownPressed: list.forceActiveFocus()
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 12
                    color: Theme.surface
                    border.width: 1
                    border.color: Theme.line
                    clip: true

                    ListView {
                        id: list
                        anchors { fill: parent; margins: 4 }
                        model: view.rows
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar {}
                        section.property: "section"
                        section.delegate: SText {
                            required property string section
                            leftPadding: 10
                            topPadding: 8
                            bottomPadding: 4
                            size: Theme.fontSmall
                            weight: 600
                            color: Theme.inkMuted
                            text: section
                        }
                        Keys.onReturnPressed: view.open()
                        Keys.onUpPressed: {
                            const i = view.rows.findIndex(r => r.id === view.selected);
                            if (i > 0) { view.selected = view.rows[i - 1].id; positionViewAtIndex(i - 1, ListView.Contain); }
                            else search.forceActiveFocus();
                        }
                        Keys.onDownPressed: {
                            const i = view.rows.findIndex(r => r.id === view.selected);
                            if (i < view.rows.length - 1) { view.selected = view.rows[i + 1].id; positionViewAtIndex(i + 1, ListView.Contain); }
                        }

                        delegate: Rectangle {
                            id: row
                            required property var modelData
                            width: ListView.view.width
                            height: 44
                            radius: 8
                            color: view.selected === modelData.id ? Theme.greenSelect
                                 : area.containsMouse ? Theme.paper : "transparent"

                            SIcon {
                                id: icon
                                anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                                size: 32
                                name: row.modelData.icon || "application-x-executable"
                            }
                            Column {
                                anchors { left: icon.right; leftMargin: 10; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                                SText {
                                    width: parent.width
                                    elide: Text.ElideRight
                                    text: row.modelData.name
                                }
                                SText {
                                    width: parent.width
                                    visible: text !== ""
                                    elide: Text.ElideRight
                                    size: Theme.fontSmall
                                    color: Theme.inkMuted
                                    text: row.modelData.comment ?? ""
                                }
                            }
                            MouseArea {
                                id: area
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: view.selected = row.modelData.id
                                onDoubleClicked: { view.selected = row.modelData.id; view.open(); }
                            }
                        }
                    }
                }

                Check {
                    id: remember
                    visible: (win.q.mimeType ?? "") !== ""
                    text: "Всегда открывать файлы этого типа этой программой"
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Item { Layout.fillWidth: true }
                    SButton {
                        text: "Отмена"
                        onClicked: win.reply({ id: "" })
                    }
                    SButton {
                        primary: true
                        text: "Открыть"
                        opacity: view.selected !== "" ? 1 : 0.5
                        onClicked: view.open()
                    }
                }
            }
        }
    }

    // ---- Мелкие части

    // Карточка файла с одной из сторон: значок или миниатюра, размер, дата.
    component FileCard: Rectangle {
        id: card
        property string label
        property var file: ({})
        property string mark

        implicitHeight: cardColumn.implicitHeight + 24
        radius: 12
        color: Theme.surface
        border.width: 1
        border.color: Theme.line

        ColumnLayout {
            id: cardColumn
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                SText {
                    Layout.fillWidth: true
                    size: Theme.fontSmall
                    weight: 600
                    color: Theme.inkMuted
                    text: card.label
                }
                Rectangle {
                    visible: card.mark !== ""
                    implicitWidth: markText.implicitWidth + 12
                    implicitHeight: markText.implicitHeight + 4
                    radius: 6
                    color: Theme.greenWash
                    SText {
                        id: markText
                        anchors.centerIn: parent
                        size: 11
                        weight: 600
                        color: Theme.green
                        text: card.mark
                    }
                }
            }
            FileIcon {
                Layout.alignment: Qt.AlignHCenter
                size: 96
                url: card.file.url ?? ""
                mimeType: card.file.mimeType ?? ""
                iconName: card.file.iconName ?? ""
                canPreview: card.file.canPreview ?? false
            }
            SText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideMiddle
                text: card.file.name ?? ""
            }
            SText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                size: Theme.fontSmall
                color: Theme.inkSoft
                text: {
                    const parts = [];
                    if (!card.file.isDir && card.file.size >= 0) parts.push(FileOps.formatSize(card.file.size));
                    const date = Format.date(card.file.modified);
                    if (date !== "") parts.push(date);
                    return parts.join(" · ");
                }
            }
        }
    }

    component Field: TextField {
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontBody
        color: Theme.ink
        placeholderTextColor: Theme.inkMuted
        selectionColor: Theme.greenSelect
        selectedTextColor: Theme.ink
        leftPadding: 10
        rightPadding: 10
        implicitHeight: 36
        background: Rectangle {
            radius: 10
            color: Theme.surface
            border.width: 1
            border.color: parent.activeFocus ? Theme.lineStrong : Theme.line
        }
    }

    component Check: Item {
        id: check
        property bool checked: false
        property string text
        implicitWidth: checkRow.implicitWidth
        implicitHeight: checkRow.implicitHeight
        Layout.fillWidth: true

        Row {
            id: checkRow
            spacing: 8
            Rectangle {
                width: 18
                height: 18
                radius: 5
                anchors.verticalCenter: parent.verticalCenter
                color: check.checked ? Theme.green : Theme.surface
                border.width: check.checked ? 0 : 1
                border.color: Theme.lineStrong
                SText {
                    anchors.centerIn: parent
                    visible: check.checked
                    size: 13
                    weight: 700
                    color: Theme.textOnGreen
                    text: "✓"
                }
            }
            SText {
                anchors.verticalCenter: parent.verticalCenter
                text: check.text
            }
        }
        MouseArea {
            anchors.fill: parent
            onClicked: check.checked = !check.checked
        }
    }
}
