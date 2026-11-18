import QtCore
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Sedmio.Files

// Окно «Файлов»: места слева, сверху навигация, строка адреса, поиск по
// папке и вид; посередине папка; внизу — сколько всего и сколько выбрано.
ApplicationWindow {
    id: win
    required property url startUrl
    // Что выделить, когда папка откроется (просили «показать файл»).
    property var selectUrls: []

    width: 1100
    height: 700
    minimumWidth: 560
    minimumHeight: 360
    visible: true
    color: Theme.paper
    title: {
        const crumbs = FileOps.crumbs(folder.url);
        return (crumbs.length > 0 ? crumbs[crumbs.length - 1].name : "") + " — Файлы";
    }

    Settings {
        id: settings
        category: "view"
        property string mode: "grid"
        property bool showHidden: false
        property string sortBy: "name"
        property bool descending: false
    }

    FolderModel {
        id: folder
        showHidden: settings.showHidden
        sortBy: settings.sortBy
        descending: settings.descending
        onShowHiddenChanged: settings.showHidden = showHidden
        onSortChanged: {
            settings.sortBy = sortBy;
            settings.descending = descending;
        }
    }

    // ---- Навигация

    property var backStack: []
    property var forwardStack: []

    function navigate(url) {
        if (url.toString() === folder.url.toString()) return;
        if (folder.url.toString() !== "") backStack = backStack.concat([folder.url]);
        forwardStack = [];
        folder.url = url;
        view.forceActiveFocus();
    }
    function back() {
        if (backStack.length === 0) return;
        forwardStack = forwardStack.concat([folder.url]);
        folder.url = backStack[backStack.length - 1];
        backStack = backStack.slice(0, -1);
    }
    function forward() {
        if (forwardStack.length === 0) return;
        backStack = backStack.concat([folder.url]);
        folder.url = forwardStack[forwardStack.length - 1];
        forwardStack = forwardStack.slice(0, -1);
    }
    readonly property string parentUrl: {
        const u = folder.url.toString().replace(/\/+$/, "");
        const scheme = u.indexOf(":/");
        const slash = u.lastIndexOf("/");
        if (scheme < 0 || slash <= scheme + 2) return "";
        if (u.startsWith("file://") && u.length <= 8) return "";
        const parent = u.substring(0, slash);
        return parent.endsWith(":/") || parent.endsWith("://") ? parent + "/" : parent;
    }
    function up() {
        if (parentUrl !== "") navigate(parentUrl);
    }

    // Открыть строку: папку — перейти, файл — открыть. Выбрано несколько
    // файлов — открыть все.
    function openRow(row) {
        if (folder.isDirAt(row)) {
            navigate(folder.urlAt(row));
            return;
        }
        const urls = folder.isSelected(row) ? folder.selectedFiles() : [folder.urlAt(row)];
        for (const url of urls) FileOps.open(url);
    }

    Component.onCompleted: {
        folder.url = startUrl;
        view.forceActiveFocus();
    }

    // ---- Действия

    readonly property var selection: folder.selectedCount > 0 ? folder.selectedUrls() : []
    readonly property bool canChange: !folder.isTrash && folder.writable

    function copySelection() { if (folder.selectedCount > 0) FileOps.copy(folder.selectedUrls()); }
    function cutSelection() { if (folder.selectedCount > 0 && canChange) FileOps.cut(folder.selectedUrls()); }
    function paste() { if (FileOps.canPaste && canChange) FileOps.paste(folder.url); }
    function trashSelection() {
        if (folder.selectedCount === 0) return;
        if (folder.isTrash) deleteSelection();
        else if (canChange) FileOps.trash(folder.selectedUrls());
    }
    function deleteSelection() {
        askDelete(folder.selectedUrls(), folder.isTrash ? "Из корзины это уже не вернуть." : "Вернуть будет нельзя.");
    }
    function askDelete(urls, reason) {
        if (urls.length === 0) return;
        const what = urls.length === 1 ? "«" + decodeURIComponent(urls[0].toString().split("/").pop()) + "»"
                                       : Format.items(urls.length);
        confirm.ask("Удалить навсегда " + what + "?", reason, "Удалить", () => FileOps.remove(urls));
    }
    function emptyTrash() {
        confirm.ask("Очистить корзину?", "Всё, что в ней лежит, удалится навсегда.", "Очистить",
                    () => FileOps.emptyTrash());
    }
    function renameSelection() {
        const row = folder.selectedCount > 0 ? folder.firstSelected() : view.currentRow;
        if (row >= 0 && canChange) {
            folder.select(row, 0);
            view.startRename(row);
        }
    }

    // Новую папку — сразу выделить и дать переименовать; переименованный
    // файл — выделить, где бы он ни оказался после сортировки.
    property string pendingName: ""
    property bool pendingRename: false
    function newFolder() {
        if (!canChange) return;
        pendingName = FileOps.createFolder(folder.url, "Новая папка");
        pendingRename = true;
    }
    function tryPending() {
        if (pendingName === "") return;
        const row = folder.rowOf(pendingName);
        if (row < 0) return;
        folder.select(row, 0);
        view.focusRow(row);
        if (pendingRename) view.startRename(row);
        pendingName = "";
        pendingRename = false;
    }
    Connections {
        target: folder
        function onRowsInserted() { Qt.callLater(win.tryPending); }
        function onLayoutChanged() { Qt.callLater(win.tryPending); }
        function onDataChanged() { Qt.callLater(win.tryPending); }
        function onLoadingChanged() {
            if (folder.loading || win.selectUrls.length === 0) return;
            const row = folder.selectUrls(win.selectUrls);
            win.selectUrls = [];
            if (row >= 0) view.focusRow(row);
        }
    }

    // Ошибки операций — полосой над папкой того окна, где работали последним.
    function showError(message) {
        banner.text = message;
        banner.visible = true;
        bannerTimer.restart();
    }
    Connections {
        target: FileOps
        function onError(message) { if (App.lastWindow === win) win.showError(message); }
        function onTrashUnavailable(urls, reason) {
            if (App.lastWindow === win) win.askDelete(urls, reason + " Вернуть будет нельзя.");
        }
    }

    // ---- Клавиши (поля ввода забирают свои: Ctrl+C в поиске — копировать текст)

    Shortcut { sequences: [StandardKey.Copy]; onActivated: win.copySelection() }
    Shortcut { sequences: [StandardKey.Cut]; onActivated: win.cutSelection() }
    Shortcut { sequences: [StandardKey.Paste]; onActivated: win.paste() }
    Shortcut { sequences: [StandardKey.SelectAll]; onActivated: folder.selectAll() }
    Shortcut { sequence: "Delete"; onActivated: win.trashSelection() }
    Shortcut { sequence: "Shift+Delete"; onActivated: win.deleteSelection() }
    Shortcut { sequence: "F2"; onActivated: win.renameSelection() }
    Shortcut { sequences: [StandardKey.Undo]; enabled: FileOps.canUndo; onActivated: FileOps.undo() }
    Shortcut { sequence: "Ctrl+Shift+N"; onActivated: win.newFolder() }
    Shortcut { sequence: "Ctrl+H"; onActivated: folder.showHidden = !folder.showHidden }
    Shortcut { sequence: "Ctrl+L"; onActivated: pathBar.edit() }
    Shortcut { sequences: ["Ctrl+F", "F3"]; onActivated: search.forceActiveFocus() }
    Shortcut { sequences: ["Alt+Left", "Back"]; onActivated: win.back() }
    Shortcut { sequences: ["Alt+Right", "Forward"]; onActivated: win.forward() }
    Shortcut { sequences: ["Alt+Up", "Backspace"]; onActivated: win.up() }
    Shortcut { sequences: ["F5", "Ctrl+R"]; onActivated: folder.reload() }
    Shortcut { sequence: "Ctrl+1"; onActivated: settings.mode = "grid" }
    Shortcut { sequence: "Ctrl+2"; onActivated: settings.mode = "list" }
    Shortcut { sequence: "Ctrl+N"; onActivated: App.openWindow(folder.url) }
    Shortcut { sequences: ["Ctrl+W", "Ctrl+Q"]; onActivated: win.close() }

    // Кнопки «назад» и «вперёд» на мыши
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.BackButton | Qt.ForwardButton
        onClicked: mouse => mouse.button === Qt.BackButton ? win.back() : win.forward()
        z: -10
    }

    // ---- Меню

    Menu { id: menu }
    ConfirmDialog { id: confirm }

    function appsMenu(row) {
        const urls = folder.isSelected(row) ? folder.selectedUrls() : [folder.urlAt(row)];
        const apps = FileOps.applications(folder.mimeAt(row)).slice(0, 8);
        const items = apps.map(app => ({
            text: app.name,
            icon: app.icon,
            action: () => FileOps.openWith(urls, app.id)
        }));
        if (items.length > 0) items.push({ separator: true });
        items.push({ text: "Другая программа…", action: () => FileOps.openWith(urls, "") });
        return items;
    }

    function showMenu(row, item, x, y) {
        let items;
        if (row >= 0 && folder.isTrash) {
            const urls = folder.selectedUrls();
            items = [
                { text: "Восстановить", icon: "edit-undo", action: () => FileOps.restore(urls) },
                { separator: true },
                { text: "Удалить навсегда", icon: "edit-delete", shortcut: "Delete", action: win.deleteSelection }
            ];
        } else if (row >= 0) {
            const single = folder.selectedCount === 1;
            const isDir = folder.isDirAt(row);
            const url = folder.urlAt(row);
            items = [
                { text: "Открыть", icon: isDir ? "folder-open" : "document-open", action: () => win.openRow(row) },
                { text: "Открыть с помощью", icon: "system-run", items: win.appsMenu(row) },
                { separator: true },
                { text: "Вырезать", icon: "edit-cut", shortcut: "Ctrl+X", enabled: win.canChange, action: win.cutSelection },
                { text: "Копировать", icon: "edit-copy", shortcut: "Ctrl+C", action: win.copySelection },
            ];
            if (single && isDir && FileOps.canPaste)
                items.push({ text: "Вставить в папку", icon: "edit-paste", action: () => FileOps.paste(url) });
            items.push({ separator: true });
            if (single)
                items.push({ text: "Переименовать", icon: "edit-rename", shortcut: "F2", enabled: win.canChange, action: win.renameSelection });
            items.push({ text: single ? "Скопировать путь" : "Скопировать пути", icon: "edit-copy-path",
                         action: () => FileOps.copyPaths(folder.selectedUrls()) });
            items.push({ separator: true });
            items.push({ text: "В корзину", icon: "user-trash", shortcut: "Delete", enabled: win.canChange, action: win.trashSelection });
            items.push({ text: "Удалить навсегда", icon: "edit-delete", shortcut: "Shift+Delete", enabled: win.canChange, action: win.deleteSelection });
        } else if (folder.isTrash) {
            items = [{ text: "Очистить корзину", icon: "trash-empty", enabled: folder.count > 0, action: win.emptyTrash }];
        } else {
            items = [];
            if (FileOps.canUndo)
                items.push({ text: FileOps.undoText, icon: "edit-undo", shortcut: "Ctrl+Z", action: () => FileOps.undo() });
            items.push({ text: "Вставить", icon: "edit-paste", shortcut: "Ctrl+V", enabled: FileOps.canPaste && win.canChange, action: win.paste });
            items.push({ text: "Новая папка", icon: "folder-new", shortcut: "Ctrl+Shift+N", enabled: win.canChange, action: win.newFolder });
            items.push({ separator: true });
            items.push({ text: "Вид", icon: "view-list-icons", items: win.viewItems() });
            items.push({ text: "Сортировка", icon: "view-sort", items: win.sortItems() });
            items.push({ text: "Скрытые файлы", icon: "view-hidden", shortcut: "Ctrl+H", checked: folder.showHidden,
                         action: () => folder.showHidden = !folder.showHidden });
            items.push({ separator: true });
            items.push({ text: "Обновить", icon: "view-refresh", shortcut: "F5", action: () => folder.reload() });
        }
        menu.items = items;
        menu.openAt(item, x, y);
    }

    function viewItems() {
        return [
            { text: "Плитки", checked: settings.mode === "grid", shortcut: "Ctrl+1", action: () => settings.mode = "grid" },
            { text: "Таблица", checked: settings.mode === "list", shortcut: "Ctrl+2", action: () => settings.mode = "list" }
        ];
    }
    function sortItems() {
        const by = key => () => {
            folder.sortBy = key;
            folder.descending = key === "date" || key === "size";
        };
        return [
            { text: "По имени", checked: folder.sortBy === "name", action: by("name") },
            { text: "По дате", checked: folder.sortBy === "date", action: by("date") },
            { text: "По размеру", checked: folder.sortBy === "size", action: by("size") },
            { text: "По типу", checked: folder.sortBy === "type", action: by("type") },
            { separator: true },
            { text: "По убыванию", checked: folder.descending, action: () => folder.descending = !folder.descending }
        ];
    }

    // Бросили файлы: на том же диске — перенести (с Ctrl — скопировать),
    // из других программ и на другой диск — скопировать.
    function handleDrop(urls, destination, info) {
        const move = info.fromUs && !info.copy && FileOps.sameDevice(urls, destination);
        FileOps.drop(urls, destination, move);
    }

    // ---- Окно

    RowLayout {
        anchors.fill: parent
        spacing: 0

        Sidebar {
            Layout.preferredWidth: 220
            Layout.fillHeight: true
            currentUrl: folder.url
            onOpenRequested: url => win.navigate(url)
            onDropped: (urls, destination, drop) => {
                drop.accept(Qt.CopyAction);
                win.handleDrop(urls, destination, { fromUs: drop.source !== null, copy: drop.proposedAction === Qt.CopyAction });
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: 8
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

                // Навигация, адрес, поиск, вид
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    ToolButton { icon: "go-previous"; enabled_: win.backStack.length > 0; onClicked: win.back() }
                    ToolButton { icon: "go-next"; enabled_: win.forwardStack.length > 0; onClicked: win.forward() }
                    ToolButton { icon: "go-up"; enabled_: win.parentUrl !== ""; onClicked: win.up() }

                    PathBar {
                        id: pathBar
                        Layout.fillWidth: true
                        Layout.leftMargin: 4
                        url: folder.url
                        onOpenRequested: url => win.navigate(url)
                    }

                    // Поиск по этой папке
                    Rectangle {
                        Layout.preferredWidth: search.activeFocus || search.text !== "" ? 240 : 180
                        Behavior on Layout.preferredWidth { NumberAnimation { duration: Theme.animFast } }
                        Layout.leftMargin: 4
                        implicitHeight: 36
                        radius: 10
                        color: Theme.surface
                        border.width: 1
                        border.color: search.activeFocus ? Theme.lineStrong : Theme.line

                        SIcon {
                            id: searchIcon
                            anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                            name: "search"
                            size: 16
                            opacity: 0.7
                        }
                        TextField {
                            id: search
                            anchors { left: searchIcon.right; right: parent.right; top: parent.top; bottom: parent.bottom; leftMargin: 2; rightMargin: 4 }
                            placeholderText: "Поиск в папке"
                            placeholderTextColor: Theme.inkMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontBody
                            color: Theme.ink
                            selectionColor: Theme.greenSelect
                            selectedTextColor: Theme.ink
                            background: null
                            verticalAlignment: TextInput.AlignVCenter
                            text: folder.filter
                            onTextEdited: folder.filter = text
                            Keys.onEscapePressed: {
                                folder.filter = "";
                                view.forceActiveFocus();
                            }
                            // Enter или стрелка вниз — к найденному
                            function toResults() {
                                view.forceActiveFocus();
                                if (folder.count > 0) {
                                    folder.select(0, 0);
                                    view.focusRow(0);
                                }
                            }
                            Keys.onDownPressed: toResults()
                            onAccepted: toResults()
                        }
                    }

                    ToolButton {
                        Layout.leftMargin: 4
                        icon: "view-list-icons"
                        checked: settings.mode === "grid"
                        onClicked: settings.mode = "grid"
                    }
                    ToolButton {
                        icon: "view-list-details"
                        checked: settings.mode === "list"
                        onClicked: settings.mode = "list"
                    }
                }

                // Ошибка операции
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
                        anchors { left: parent.left; right: bannerClose.left; leftMargin: 12; rightMargin: 8; verticalCenter: parent.verticalCenter }
                        wrapMode: Text.Wrap
                        color: Theme.ink
                    }
                    SText {
                        id: bannerClose
                        anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                        text: "✕"
                        size: 12
                        color: Theme.inkSoft
                        MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: banner.visible = false }
                    }
                    Timer { id: bannerTimer; interval: 8000; onTriggered: banner.visible = false }
                }

                FolderView {
                    id: view
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    folder: folder
                    mode: settings.mode
                    onOpenRequested: row => win.openRow(row)
                    onContextMenuRequested: (row, item, x, y) => win.showMenu(row, item, x, y)
                    onDropRequested: (urls, destination, info) => win.handleDrop(urls, destination, info)
                    onRenameFailed: message => win.showError(message)
                    onRenamed: newName => {
                        win.pendingName = newName;
                        win.pendingRename = false;
                    }
                }

                // Строка состояния
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 6
                    Layout.rightMargin: 6
                    spacing: 8

                    SText {
                        Layout.fillWidth: true
                        size: Theme.fontSmall
                        color: Theme.inkMuted
                        text: folder.loading && folder.count === 0 ? "Открываю…"
                            : folder.selectedCount > 0
                                ? "Выбрано " + Format.number(folder.selectedCount) + " из " + Format.number(folder.count)
                                  + (folder.selectedSize > 0 ? " · " + FileOps.formatSize(folder.selectedSize) : "")
                            : Format.items(folder.count)
                    }
                    SText {
                        visible: FileOps.cutUrls.length > 0
                        size: Theme.fontSmall
                        color: Theme.inkMuted
                        text: "Вырезано: " + Format.items(FileOps.cutUrls.length) + " — вставьте Ctrl+V"
                    }
                }
            }
        }
    }
}
