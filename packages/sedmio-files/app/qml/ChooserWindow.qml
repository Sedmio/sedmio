import QtCore
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Sedmio.Files
import Sedmio.Style

// Окно выбора файлов для других программ («Открыть», «Сохранить как»):
// те же места, адрес и папка, что в «Файлах», внизу — имя файла, вид
// файлов и кнопки. Отвечает через session (portal.cpp).
ApplicationWindow {
    id: win
    required property QtObject session
    // open — выбрать файлы (или папку, directory); save — куда сохранить
    // файл; saveFiles — в какую папку сохранить несколько (files).
    property string mode: "open"
    property string requestedTitle
    property string acceptLabel
    property bool multiple: false
    property bool directory: false
    // [{name, patterns: ["*.png"], mimes: ["image/png"]}]
    property var filters: []
    property int filterIndex: -1
    // [{id, label, items: [{id, label}], initial}]; без items — галочка.
    property var choices: []
    property url startFolder
    property string currentName
    property var files: []

    readonly property bool saving: mode !== "open"
    readonly property bool choosingFolder: (mode === "open" && directory) || mode === "saveFiles"

    width: chooserSettings.width
    height: chooserSettings.height
    minimumWidth: 560
    minimumHeight: 380
    color: Theme.paper
    title: requestedTitle !== "" ? requestedTitle
         : mode === "save" ? "Сохранить файл"
         : choosingFolder ? "Выбрать папку"
         : multiple ? "Открыть файлы" : "Открыть файл"

    Settings {
        id: viewSettings
        category: "view"
        property string mode: "grid"
        property bool showHidden: false
        property string sortBy: "name"
        property bool descending: false
    }
    Settings {
        id: chooserSettings
        category: "chooser"
        property string lastFolder: ""
        property int width: 900
        property int height: 600
    }

    readonly property FolderModel folder: tab.folder
    readonly property bool localFolder: folder.url.toString().startsWith("file:")
    // Папка на месте (не удалена, флешку не вынули).
    function folderExists() {
        return session.kind(folder.url) === 2;
    }

    // ---- Ответ

    property bool answered: false
    property var choiceValues: ({})

    function finish(urls) {
        if (answered) return;
        answered = true;
        chooserSettings.lastFolder = folder.url.toString();
        chooserSettings.width = win.width;
        chooserSettings.height = win.height;
        session.finish(true, urls, choosingFolder ? -1 : filterIndex, choiceValues);
    }
    function cancel() {
        if (answered) return;
        answered = true;
        session.finish(false, [], filterIndex, choiceValues);
    }
    onClosing: cancel()

    // ---- Фильтр по виду файлов

    function filterAt(index) {
        return index >= 0 && index < filters.length ? filters[index] : null;
    }
    // «*.png» → «png»; у фильтра без простого шаблона — пусто.
    function extensionOf(filter) {
        if (!filter) return "";
        for (const p of filter.patterns) {
            const m = /^\*\.([A-Za-z0-9_+-]+)$/.exec(p);
            if (m) return m[1];
        }
        return "";
    }
    // Сменили вид файлов при сохранении — сменить и расширение в имени.
    onFilterIndexChanged: {
        if (mode !== "save") return;
        // Фильтр — по индексу, а не привязкой: та может пересчитаться позже.
        const ext = extensionOf(filterAt(filterIndex));
        const name = nameField.text;
        const dot = name.lastIndexOf(".");
        if (ext === "" || dot <= 0) return;
        nameField.text = name.substring(0, dot + 1) + ext;
    }

    // ---- Принять

    function accept() {
        if (!localFolder) {
            showError("Выберите папку на этом компьютере.");
            return;
        }
        if (choosingFolder && !folderExists()) {
            showError("Этой папки нет. Выберите другую.");
            return;
        }
        if (mode === "open" && directory) {
            const rows = folder.selectedUrls();
            const one = folder.selectedCount === 1 && folder.isDirAt(folder.firstSelected());
            finish(one ? rows : [folder.url]);
            return;
        }
        if (mode === "open") {
            const chosen = folder.selectedFiles();
            if (chosen.length > 0) {
                finish(multiple ? chosen : [chosen[0]]);
                return;
            }
            // Выбрана папка — войти в неё.
            const row = folder.firstSelected();
            if (row >= 0 && folder.isDirAt(row)) tab.navigate(folder.urlAt(row));
            return;
        }
        if (mode === "saveFiles") {
            const targets = win.files.map(name => session.child(folder.url, name));
            const existing = targets.filter(u => session.kind(u) !== 0);
            if (existing.length === 0) {
                finish(targets);
                return;
            }
            confirm.ask(existing.length === 1 ? "Заменить «" + decodeURIComponent(existing[0].toString().split("/").pop()) + "»?"
                                              : "Заменить " + Format.number(existing.length) + " " + Format.plural(existing.length, "файл", "файла", "файлов") + "?",
                        "В этой папке уже есть файлы с такими именами.", "Заменить", () => finish(targets));
            return;
        }
        // Сохранить один файл.
        let name = nameField.text.trim();
        if (name === "") {
            nameField.forceActiveFocus();
            return;
        }
        const ext = extensionOf(filterAt(filterIndex));
        if (ext !== "" && name.indexOf(".") < 0) name += "." + ext;
        const target = session.resolve(folder.url, name);
        const kind = session.kind(target);
        if (kind === 2) {
            // Ввели путь к папке — перейти в неё.
            tab.navigate(target);
            nameField.text = "";
            return;
        }
        if (session.kind(session.parentOf(target)) !== 2) {
            showError("Нет такой папки: " + FileOps.prettyPath(session.parentOf(target)));
            return;
        }
        if (kind === 1) {
            confirm.ask("Заменить «" + name.split("/").pop() + "»?", "Файл с таким именем уже есть в этой папке.", "Заменить",
                        () => finish([target]));
            return;
        }
        finish([target]);
    }

    readonly property string acceptText: acceptLabel !== "" ? acceptLabel
        : mode === "open" ? (directory ? "Выбрать" : "Открыть")
        : "Сохранить"
    readonly property bool canAccept: localFolder && (mode === "save" ? nameField.text.trim() !== ""
                                                     : mode === "open" && !directory ? folder.selectedCount > 0
                                                     : true)

    // Двойной щелчок, Enter: папка — войти, файл — выбрать.
    function openRow(row) {
        if (folder.isDirAt(row)) {
            tab.navigate(folder.urlAt(row));
            return;
        }
        // Enter на строке под курсором — выбрать именно её, а не выделенную раньше.
        if (!folder.isSelected(row)) folder.select(row, 0);
        if (mode === "open" && !directory) {
            accept();
        } else if (mode === "save") {
            nameField.text = folder.nameAt(row);
            accept();
        }
    }

    // При сохранении выбрали файл — его имя в поле (перезаписать его).
    Connections {
        target: win.folder
        enabled: win.mode === "save"
        function onSelectionChanged() {
            const row = win.folder.firstSelected();
            if (win.folder.selectedCount === 1 && row >= 0 && !win.folder.isDirAt(row))
                nameField.text = win.folder.nameAt(row);
        }
    }

    function showError(message) {
        banner.text = message;
        banner.visible = true;
        bannerTimer.restart();
    }

    Component.onCompleted: {
        const values = {};
        for (const c of choices) values[c.id] = c.initial !== "" ? c.initial : (c.items.length > 0 ? c.items[0].id : "false");
        choiceValues = values;

        nameField.text = currentName;
        if (mode === "save") {
            // Выделить имя без расширения — сразу набирать своё.
            const dot = currentName.lastIndexOf(".");
            nameField.forceActiveFocus();
            nameField.select(0, dot > 0 ? dot : currentName.length);
        } else {
            tab.view.forceActiveFocus();
        }
    }

    // ---- Клавиши

    // Escape в поле адреса или имени папки — отменить правку, а не весь выбор.
    Shortcut {
        sequence: "Escape"
        enabled: !pathBar.editing && tab.view.renamingRow < 0
        onActivated: win.cancel()
    }
    Shortcut { sequence: "Ctrl+L"; onActivated: pathBar.edit() }
    Shortcut { sequences: ["Alt+Left", "Back"]; onActivated: tab.back() }
    Shortcut { sequences: ["Alt+Right", "Forward"]; onActivated: tab.forward() }
    Shortcut { sequence: "Alt+Up"; onActivated: tab.up() }
    Shortcut { sequence: "Ctrl+H"; onActivated: viewSettings.showHidden = !viewSettings.showHidden }
    Shortcut { sequences: ["F5", "Ctrl+R"]; onActivated: folder.reload() }
    Shortcut { sequence: "Ctrl+Shift+N"; enabled: win.saving; onActivated: win.newFolder() }

    function newFolder() {
        if (!folder.writable) return;
        tab.pendingName = FileOps.createFolder(folder.url, "Новая папка");
        tab.pendingRename = true;
    }

    ConfirmDialog { id: confirm }

    QuickLook {
        id: quickLook
        folder: win.folder
        onRowChosen: row => {
            win.folder.select(row, 0);
            tab.view.focusRow(row);
        }
        onOpenRequested: row => win.openRow(row)
        onClosed: tab.view.forceActiveFocus()
    }

    // ---- Окно

    // Заголовка у окна нет: верх окна — за него (WindowDragArea), сверху —
    // полоса инструментов с кнопками окна.
    WindowDragArea {
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 52
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        Sidebar {
            heading: win.title
            Layout.preferredWidth: 200
            Layout.fillHeight: true
            currentUrl: folder.url
            onOpenRequested: url => tab.navigate(url)
            onOpenInNewTabRequested: url => tab.navigate(url)
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 8
                Layout.rightMargin: 8
                Layout.bottomMargin: 8
                spacing: 4

                ToolButton { icon: "go-previous"; enabled_: tab.backStack.length > 0; onClicked: tab.back() }
                ToolButton { icon: "go-next"; enabled_: tab.forwardStack.length > 0; onClicked: tab.forward() }
                ToolButton { icon: "go-up"; enabled_: tab.parentUrl !== ""; onClicked: tab.up() }

                PathBar {
                    id: pathBar
                    Layout.fillWidth: true
                    Layout.leftMargin: 4
                    url: folder.url
                    onOpenRequested: url => tab.navigate(url)
                    onOpenInNewTabRequested: url => tab.navigate(url)
                }

                ToolButton {
                    Layout.leftMargin: 4
                    visible: win.saving
                    icon: "folder-new"
                    enabled_: folder.writable
                    onClicked: win.newFolder()
                }
                ToolButton {
                    Layout.leftMargin: win.saving ? 0 : 4
                    icon: "view-list-icons"
                    checked: viewSettings.mode === "grid"
                    onClicked: viewSettings.mode = "grid"
                }
                ToolButton {
                    icon: "view-list-details"
                    checked: viewSettings.mode === "list"
                    onClicked: viewSettings.mode = "list"
                }
                WindowControls { Layout.leftMargin: 8 }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.rightMargin: 8
                Layout.bottomMargin: 8
                radius: 14
                color: Theme.surface
                border.width: 1
                border.color: Theme.line

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 6

                    Rectangle {
                        id: banner
                        property alias text: bannerText.text
                        Layout.fillWidth: true
                        visible: false
                        implicitHeight: bannerText.implicitHeight + 18
                        radius: 10
                        color: Theme.terracottaSoft
                        SText {
                            id: bannerText
                            anchors { left: parent.left; right: parent.right; leftMargin: 12; rightMargin: 12; verticalCenter: parent.verticalCenter }
                            wrapMode: Text.Wrap
                        }
                        Timer { id: bannerTimer; interval: 6000; onTriggered: banner.visible = false }
                    }

                    FolderTab {
                        id: tab
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        // Первая из папок, что есть на месте.
                        startUrl: win.session.kind(win.startFolder) === 2 ? win.startFolder
                                : win.session.kind(chooserSettings.lastFolder) === 2 ? chooserSettings.lastFolder
                                : FileOps.homeUrl
                        mode: viewSettings.mode
                        showHidden: viewSettings.showHidden
                        sortBy: viewSettings.sortBy
                        descending: viewSettings.descending
                        onOpenRequested: row => win.openRow(row)
                        onPreviewRequested: row => quickLook.show(row)
                        onRenameFailed: message => win.showError(message)
                        onSortRequested: key => {
                            if (viewSettings.sortBy === key) {
                                viewSettings.descending = !viewSettings.descending;
                            } else {
                                viewSettings.sortBy = key;
                                viewSettings.descending = key === "date" || key === "size";
                            }
                        }
                        Component.onCompleted: {
                            folder.singleSelection = !(win.mode === "open" && win.multiple && !win.directory);
                            folder.dirsOnly = win.choosingFolder;
                            win.applyFilter();
                        }
                    }

                    // Имя файла, вид файлов, выборы программы, кнопки.
                    GridLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        Layout.leftMargin: 4
                        Layout.rightMargin: 4
                        columns: 2
                        columnSpacing: 10
                        rowSpacing: 8

                        SText {
                            visible: win.mode === "save"
                            text: "Имя файла"
                            color: Theme.inkSoft
                        }
                        Field {
                            id: nameField
                            visible: win.mode === "save"
                            Layout.fillWidth: true
                            onAccepted: win.accept()
                        }

                        SText {
                            visible: win.filters.length > 0 && !win.choosingFolder
                            text: "Вид файлов"
                            color: Theme.inkSoft
                        }
                        Choice {
                            visible: win.filters.length > 0 && !win.choosingFolder
                            Layout.fillWidth: true
                            model: win.filters.map(f => f.name)
                            currentIndex: win.filterIndex
                            onActivated: index => {
                                win.filterIndex = index;
                                win.applyFilter();
                            }
                        }

                        Repeater {
                            model: win.choices
                            delegate: RowLayout {
                                id: choiceRow
                                required property var modelData
                                Layout.columnSpan: 2
                                Layout.fillWidth: true
                                spacing: 10

                                SText {
                                    visible: choiceRow.modelData.items.length > 0
                                    text: choiceRow.modelData.label
                                    color: Theme.inkSoft
                                }
                                Choice {
                                    visible: choiceRow.modelData.items.length > 0
                                    Layout.fillWidth: true
                                    model: choiceRow.modelData.items.map(i => i.label)
                                    currentIndex: Math.max(0, choiceRow.modelData.items.findIndex(i => i.id === win.choiceValues[choiceRow.modelData.id]))
                                    onActivated: index => win.setChoice(choiceRow.modelData.id, choiceRow.modelData.items[index].id)
                                }
                                CheckBox {
                                    visible: choiceRow.modelData.items.length === 0
                                    checked: win.choiceValues[choiceRow.modelData.id] === "true"
                                    onToggled: win.setChoice(choiceRow.modelData.id, checked ? "true" : "false")
                                    contentItem: SText {
                                        leftPadding: parent.indicator.width + 6
                                        text: choiceRow.modelData.label
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                }
                            }
                        }

                        RowLayout {
                            Layout.columnSpan: 2
                            Layout.fillWidth: true
                            spacing: 8

                            SText {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                size: Theme.fontSmall
                                color: Theme.inkMuted
                                text: win.mode === "saveFiles" ? "Сохранить " + Format.number(win.files.length) + " " + Format.plural(win.files.length, "файл", "файла", "файлов") + " в эту папку"
                                    : folder.selectedCount > 1 ? "Выбрано " + Format.number(folder.selectedCount)
                                    : ""
                            }
                            SButton {
                                text: "Отмена"
                                onClicked: win.cancel()
                            }
                            SButton {
                                text: win.acceptText
                                primary: true
                                opacity: win.canAccept ? 1 : 0.5
                                onClicked: if (win.canAccept) win.accept()
                            }
                        }
                    }
                }
            }
        }
    }

    function setChoice(id, value) {
        const values = Object.assign({}, choiceValues);
        values[id] = value;
        choiceValues = values;
    }

    function applyFilter() {
        const f = filterAt(filterIndex);
        folder.nameFilters = f ? f.patterns : [];
        folder.mimeFilters = f ? f.mimes : [];
    }

    // Поле ввода в стиле «Файлов».
    component Field: TextField {
        implicitHeight: 36
        leftPadding: 12
        rightPadding: 12
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontBody
        color: Theme.ink
        selectionColor: Theme.greenSelect
        selectedTextColor: Theme.ink
        verticalAlignment: TextInput.AlignVCenter
        background: Rectangle {
            radius: 10
            color: Theme.surface
            border.width: 1
            border.color: parent.activeFocus ? Theme.lineStrong : Theme.line
        }
    }

    // Выпадающий список в стиле «Файлов».
    component Choice: ComboBox {
        id: combo
        implicitHeight: 36
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontBody
        background: Rectangle {
            radius: 10
            color: combo.hovered ? Theme.paper : Theme.surface
            border.width: 1
            border.color: combo.activeFocus ? Theme.lineStrong : Theme.line
        }
        contentItem: SText {
            leftPadding: 12
            rightPadding: combo.indicator.width + 6
            text: combo.displayText
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
        }
        popup.background: Rectangle {
            radius: 10
            color: Theme.surface
            border.width: 1
            border.color: Theme.line
        }
        delegate: ItemDelegate {
            required property int index
            required property var modelData
            width: combo.width
            // Подсветка — с полями: не упирается в скруглённые углы списка.
            leftInset: 4
            rightInset: 4
            topInset: 2
            bottomInset: 2
            highlighted: combo.highlightedIndex === index
            contentItem: SText {
                text: modelData
                weight: combo.currentIndex === index ? 600 : 400
                elide: Text.ElideRight
            }
            background: Rectangle {
                radius: 8
                color: highlighted ? Theme.greenWash : Qt.alpha(Theme.greenWash, 0)
            }
        }
    }
}
