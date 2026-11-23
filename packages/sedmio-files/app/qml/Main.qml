import QtCore
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Sedmio.Files
import Sedmio.Style

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
    title: (tab ? tab.title : "") + " — Файлы"

    Settings {
        id: settings
        category: "view"
        property string mode: "grid"
        property bool showHidden: false
        property string sortBy: "name"
        property bool descending: false
    }

    // ---- Вкладки

    // start — с какой папки вкладка начиналась; где она сейчас — у самой вкладки.
    ListModel { id: tabsModel }
    property int currentTab: 0
    // Закрытые вкладки — вернуть по Ctrl+Shift+T.
    property var closedTabs: []

    readonly property FolderTab tab: tabsRepeater.count > 0 && currentTab < tabsRepeater.count
        ? tabsRepeater.itemAt(currentTab) : null
    // Пока вкладка создаётся, привязкам нужна хоть какая-то модель.
    FolderModel { id: noFolder }
    readonly property FolderModel folder: tab ? tab.folder : noFolder
    readonly property FolderView view: tab ? tab.view : null

    function newTab(url, background) {
        tabsModel.insert(currentTab + 1, { start: url.toString() });
        if (!background) currentTab = currentTab + 1;
    }
    function closeTab(index) {
        if (tabsModel.count <= 1) {
            win.close();
            return;
        }
        closedTabs = closedTabs.concat([tabsRepeater.itemAt(index).folder.url.toString()]).slice(-20);
        if (index < currentTab || (index === currentTab && index === tabsModel.count - 1))
            currentTab = currentTab - 1;
        tabsModel.remove(index);
    }
    function reopenTab() {
        if (closedTabs.length === 0) return;
        const url = closedTabs[closedTabs.length - 1];
        closedTabs = closedTabs.slice(0, -1);
        newTab(url, false);
    }
    function switchTab(delta) {
        const n = tabsModel.count;
        currentTab = (currentTab + delta + n) % n;
    }
    onCurrentTabChanged: Qt.callLater(() => { if (view) view.forceActiveFocus(); })

    // ---- Навигация (в текущей вкладке)

    function navigate(url) { if (tab) tab.navigate(url); }
    function back() { if (tab) tab.back(); }
    function forward() { if (tab) tab.forward(); }
    function up() { if (tab) tab.up(); }

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
        tabsModel.append({ start: startUrl.toString() });
        tabsRepeater.itemAt(0).selectUrls = win.selectUrls;
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
        if (!view) return;
        const row = folder.selectedCount > 0 ? folder.firstSelected() : view.currentRow;
        if (row >= 0 && canChange) {
            folder.select(row, 0);
            view.startRename(row);
        }
    }

    // Новую папку — сразу выделить и дать переименовать (см. FolderTab).
    function newFolder() {
        if (!canChange || !tab) return;
        tab.pendingName = FileOps.createFolder(folder.url, "Новая папка");
        tab.pendingRename = true;
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
    Shortcut { sequence: "Ctrl+H"; onActivated: settings.showHidden = !settings.showHidden }
    Shortcut { sequence: "Ctrl+L"; onActivated: pathBar.edit() }
    Shortcut { sequences: ["Ctrl+F", "F3"]; onActivated: search.forceActiveFocus() }
    Shortcut { sequences: ["Alt+Left", "Back"]; onActivated: win.back() }
    Shortcut { sequences: ["Alt+Right", "Forward"]; onActivated: win.forward() }
    Shortcut { sequences: ["Alt+Up", "Backspace"]; onActivated: win.up() }
    Shortcut { sequences: ["F5", "Ctrl+R"]; onActivated: folder.reload() }
    Shortcut { sequence: "Ctrl+1"; onActivated: settings.mode = "grid" }
    Shortcut { sequence: "Ctrl+2"; onActivated: settings.mode = "list" }
    Shortcut { sequence: "Ctrl+N"; onActivated: App.openWindow(folder.url) }
    Shortcut { sequence: "Ctrl+T"; onActivated: win.newTab(folder.url, false) }
    Shortcut { sequence: "Ctrl+W"; onActivated: win.closeTab(win.currentTab) }
    Shortcut { sequence: "Ctrl+Shift+T"; onActivated: win.reopenTab() }
    Shortcut { sequences: ["Ctrl+Tab", "Ctrl+PgDown"]; onActivated: win.switchTab(1) }
    Shortcut { sequences: ["Ctrl+Shift+Tab", "Ctrl+PgUp"]; onActivated: win.switchTab(-1) }
    Shortcut { sequence: "Ctrl+Q"; onActivated: win.close() }
    Shortcut { sequences: ["Alt+Return", "Alt+Enter"]; onActivated: win.showProperties() }
    // Alt+1…9 — вкладка по номеру
    Repeater {
        model: 9
        Item {
            required property int index
            Shortcut {
                sequence: "Alt+" + (index + 1)
                enabled: index < tabsModel.count
                onActivated: win.currentTab = index
            }
        }
    }

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

    // Свойства выбранного, а если ничего не выбрано — этой папки.
    function showProperties() {
        App.showProperties(folder.selectedCount > 0 ? folder.selectedUrls() : [folder.url]);
    }

    QuickLook {
        id: quickLook
        folder: win.folder
        onRowChosen: row => {
            win.folder.select(row, 0);
            if (win.view) win.view.focusRow(row);
        }
        onOpenRequested: row => win.openRow(row)
        onClosed: if (win.view) win.view.forceActiveFocus()
    }
    // Ушли в другую папку или вкладку — показывать уже нечего.
    onFolderChanged: quickLook.close()
    Connections {
        target: win.folder
        function onUrlChanged() { quickLook.close(); }
    }

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
                { text: "Просмотр", icon: "document-preview", shortcut: "Пробел", action: () => quickLook.show(row) }
            ];
            if (isDir)
                items.push({ text: "Открыть в новой вкладке", icon: "tab-new", shortcut: "Средняя кнопка",
                             action: () => win.newTab(url, false) });
            items = items.concat([
                { text: "Открыть с помощью", icon: "system-run", items: win.appsMenu(row) },
                { separator: true },
                { text: "Вырезать", icon: "edit-cut", shortcut: "Ctrl+X", enabled: win.canChange, action: win.cutSelection },
                { text: "Копировать", icon: "edit-copy", shortcut: "Ctrl+C", action: win.copySelection },
            ]);
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
            items.push({ separator: true });
            items.push({ text: "Свойства", icon: "document-properties", shortcut: "Alt+Enter", action: win.showProperties });
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
            items.push({ text: "Скрытые файлы", icon: "view-hidden", shortcut: "Ctrl+H", checked: settings.showHidden,
                         action: () => settings.showHidden = !settings.showHidden });
            items.push({ separator: true });
            items.push({ text: "Обновить", icon: "view-refresh", shortcut: "F5", action: () => folder.reload() });
            items.push({ text: "Новая вкладка", icon: "tab-new", shortcut: "Ctrl+T", action: () => win.newTab(folder.url, false) });
            items.push({ separator: true });
            items.push({ text: "Свойства папки", icon: "document-properties", shortcut: "Alt+Enter",
                         action: () => App.showProperties([folder.url]) });
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
            settings.sortBy = key;
            settings.descending = key === "date" || key === "size";
        };
        return [
            { text: "По имени", checked: folder.sortBy === "name", action: by("name") },
            { text: "По дате", checked: folder.sortBy === "date", action: by("date") },
            { text: "По размеру", checked: folder.sortBy === "size", action: by("size") },
            { text: "По типу", checked: folder.sortBy === "type", action: by("type") },
            { separator: true },
            { text: "По убыванию", checked: settings.descending, action: () => settings.descending = !settings.descending }
        ];
    }

    // Заголовок столбца: тот же — сменить направление, другой — сортировать по нему.
    function sortBy(key) {
        if (settings.sortBy === key) {
            settings.descending = !settings.descending;
        } else {
            settings.sortBy = key;
            settings.descending = key === "date" || key === "size";
        }
    }

    // Бросили файлы: на том же диске — перенести (с Ctrl — скопировать),
    // из других программ и на другой диск — скопировать.
    function handleDrop(urls, destination, info) {
        const move = info.fromUs && !info.copy && FileOps.sameDevice(urls, destination);
        FileOps.drop(urls, destination, move);
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
            heading: "Файлы"
            Layout.preferredWidth: 220
            Layout.fillHeight: true
            currentUrl: folder.url
            onOpenRequested: url => win.navigate(url)
            onOpenInNewTabRequested: url => win.newTab(url, true)
            onDropped: (urls, destination, drop) => {
                drop.accept(Qt.CopyAction);
                win.handleDrop(urls, destination, { fromUs: drop.source !== null, copy: drop.proposedAction === Qt.CopyAction });
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // Навигация, адрес, поиск, вид
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 8
                Layout.rightMargin: 8
                Layout.bottomMargin: 8
                spacing: 4

                ToolButton { icon: "go-previous"; enabled_: !!win.tab && win.tab.backStack.length > 0; onClicked: win.back() }
                ToolButton { icon: "go-next"; enabled_: !!win.tab && win.tab.forwardStack.length > 0; onClicked: win.forward() }
                ToolButton { icon: "go-up"; enabled_: !!win.tab && win.tab.parentUrl !== ""; onClicked: win.up() }

                PathBar {
                    id: pathBar
                    Layout.fillWidth: true
                    Layout.leftMargin: 4
                    url: folder.url
                    onOpenRequested: url => win.navigate(url)
                    onOpenInNewTabRequested: url => win.newTab(url, true)
                }

                // Поиск по этой папке
                Rectangle {
                    // Узкое окно — поиск уступает место адресу.
                    Layout.preferredWidth: Math.min(search.activeFocus || search.text !== "" ? 240 : 180,
                                                    Math.max(120, parent.width * 0.28))
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
                        symbolic: true
                        color: Theme.inkMuted
                    }
                    TextField {
                        id: search
                        anchors { left: searchIcon.right; right: parent.right; top: parent.top; bottom: parent.bottom; leftMargin: 2; rightMargin: 4 }
                        placeholderText: width < 110 ? "Поиск" : "Поиск в папке"
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
                            if (view) view.forceActiveFocus();
                        }
                        // Enter или стрелка вниз — к найденному
                        function toResults() {
                            if (!view) return;
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

                    // Вкладки — когда их больше одной
                    RowLayout {
                        Layout.fillWidth: true
                        visible: tabsModel.count > 1
                        spacing: 4

                        Repeater {
                            model: tabsModel
                            delegate: TabChip {}
                        }
                        ToolButton {
                            icon: "list-add"
                            onClicked: win.newTab(win.folder.url, false)
                        }
                        Item { Layout.fillWidth: true }
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

                    // Папки вкладок; видна текущая.
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        Repeater {
                            id: tabsRepeater
                            model: tabsModel
                            delegate: FolderTab {
                                id: folderTab
                                required property int index
                                required property string start
                                anchors.fill: parent
                                startUrl: start
                                visible: index === win.currentTab
                                focus: visible
                                mode: settings.mode
                                showHidden: settings.showHidden
                                sortBy: settings.sortBy
                                descending: settings.descending
                                onOpenRequested: row => win.openRow(row)
                                onContextMenuRequested: (row, item, x, y) => win.showMenu(row, item, x, y)
                                onDropRequested: (urls, destination, info) => win.handleDrop(urls, destination, info)
                                onRenameFailed: message => win.showError(message)
                                onSortRequested: key => win.sortBy(key)
                                onOpenInNewTabRequested: url => win.newTab(url, true)
                                onPreviewRequested: row => quickLook.show(row)
                            }
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

    // Ярлык вкладки: щелчок — перейти, средняя кнопка или ✕ — закрыть.
    // Тащат файлы и держат над ярлыком — вкладка открывается; бросили —
    // файлы ложатся в её папку.
    component TabChip: Rectangle {
        id: chip
        required property int index
        readonly property bool current: index === win.currentTab
        // Сама вкладка (count — чтобы пересчитать, когда её создадут).
        readonly property FolderTab tab: tabsRepeater.count, tabsRepeater.itemAt(index)
        readonly property url url: tab ? tab.folder.url : ""

        Layout.fillWidth: true
        Layout.maximumWidth: 220
        Layout.minimumWidth: 60
        implicitHeight: 32
        radius: 9
        color: current ? Theme.paperDeep
             : tabDrop.containsDrag ? Theme.greenWash
             : chipArea.containsMouse ? Theme.paper : Qt.alpha(Theme.paper, 0)
        Behavior on color { ColorAnimation { duration: Theme.animFast } }

        SIcon {
            id: chipIcon
            anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
            size: 16
            name: "folder"
            opacity: chip.current ? 1 : 0.7
        }
        SText {
            anchors { left: chipIcon.right; leftMargin: 6; right: close.left; rightMargin: 4; verticalCenter: parent.verticalCenter }
            text: chip.tab ? chip.tab.title : ""
            elide: Text.ElideRight
            size: 13
            weight: chip.current ? 600 : 450
            color: chip.current ? Theme.ink : Theme.inkSoft
        }

        MouseArea {
            id: chipArea
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
            onClicked: mouse => mouse.button === Qt.MiddleButton ? win.closeTab(chip.index) : win.currentTab = chip.index
        }

        Rectangle {
            id: close
            anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
            width: 20
            height: 20
            radius: 6
            visible: chip.current || chipArea.containsMouse || closeArea.containsMouse
            color: closeArea.containsMouse ? Theme.line : Qt.alpha(Theme.line, 0)
            SText {
                anchors.centerIn: parent
                text: "✕"
                size: 11
                color: Theme.inkSoft
            }
            MouseArea {
                id: closeArea
                anchors.fill: parent
                hoverEnabled: true
                onClicked: win.closeTab(chip.index)
            }
        }

        DropArea {
            id: tabDrop
            anchors.fill: parent
            keys: ["text/uri-list"]
            onEntered: if (!chip.current) openTimer.restart()
            onExited: openTimer.stop()
            onDropped: drop => {
                openTimer.stop();
                drop.accept(Qt.CopyAction);
                win.handleDrop(drop.urls, chip.url, { fromUs: drop.source !== null, copy: drop.proposedAction === Qt.CopyAction });
            }
        }
        Timer {
            id: openTimer
            interval: 700
            onTriggered: win.currentTab = chip.index
        }
    }
}
