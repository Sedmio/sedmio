import QtQuick
import Sedmio.Files

// Одна вкладка окна: своя папка, своя история «назад/вперёд», своё
// выделение. Вид, сортировка и скрытые файлы — общие на все вкладки
// (настройки окна), их сюда передаёт Main.qml.
FocusScope {
    id: tab
    required property url startUrl
    // Что выделить, когда папка откроется (просили «показать файл»).
    property var selectUrls: []

    property alias mode: folderView.mode
    property alias showHidden: model.showHidden
    property alias sortBy: model.sortBy
    property alias descending: model.descending

    readonly property FolderModel folder: model
    readonly property FolderView view: folderView

    // Имя папки — для заголовка окна и ярлыка вкладки.
    readonly property string title: {
        const crumbs = FileOps.crumbs(model.url);
        return crumbs.length > 0 ? crumbs[crumbs.length - 1].name : "";
    }

    signal openRequested(int row)
    signal contextMenuRequested(int row, Item item, real x, real y)
    signal dropRequested(var urls, url destination, var info)
    signal renameFailed(string message)
    signal sortRequested(string key)
    signal openInNewTabRequested(url url)
    signal previewRequested(int row)

    // ---- Навигация

    property var backStack: []
    property var forwardStack: []

    function navigate(url) {
        if (url.toString() === model.url.toString()) return;
        if (model.url.toString() !== "") backStack = backStack.concat([model.url]);
        forwardStack = [];
        model.url = url;
        folderView.forceActiveFocus();
    }
    function back() {
        if (backStack.length === 0) return;
        forwardStack = forwardStack.concat([model.url]);
        model.url = backStack[backStack.length - 1];
        backStack = backStack.slice(0, -1);
    }
    function forward() {
        if (forwardStack.length === 0) return;
        backStack = backStack.concat([model.url]);
        model.url = forwardStack[forwardStack.length - 1];
        forwardStack = forwardStack.slice(0, -1);
    }
    readonly property string parentUrl: {
        const u = model.url.toString().replace(/\/+$/, "");
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

    // ---- Новая папка и переименованный файл — выделить, где бы они ни
    // оказались после сортировки (и сразу дать переименовать новую).

    property string pendingName: ""
    property bool pendingRename: false
    function tryPending() {
        if (pendingName === "") return;
        const row = model.rowOf(pendingName);
        if (row < 0) return;
        model.select(row, 0);
        folderView.focusRow(row);
        if (pendingRename) folderView.startRename(row);
        pendingName = "";
        pendingRename = false;
    }

    FolderModel {
        id: model
        Component.onCompleted: url = tab.startUrl
    }

    Connections {
        target: model
        function onRowsInserted() { Qt.callLater(tab.tryPending); }
        function onLayoutChanged() { Qt.callLater(tab.tryPending); }
        function onDataChanged() { Qt.callLater(tab.tryPending); }
        function onLoadingChanged() {
            if (model.loading || tab.selectUrls.length === 0) return;
            const row = model.selectUrls(tab.selectUrls);
            tab.selectUrls = [];
            if (row >= 0) folderView.focusRow(row);
        }
    }

    FolderView {
        id: folderView
        anchors.fill: parent
        focus: true
        folder: model
        onOpenRequested: row => tab.openRequested(row)
        onContextMenuRequested: (row, item, x, y) => tab.contextMenuRequested(row, item, x, y)
        onDropRequested: (urls, destination, info) => tab.dropRequested(urls, destination, info)
        onRenameFailed: message => tab.renameFailed(message)
        onRenamed: newName => {
            tab.pendingName = newName;
            tab.pendingRename = false;
        }
        onSortRequested: key => tab.sortRequested(key)
        onOpenInNewTabRequested: url => tab.openInNewTabRequested(url)
        onPreviewRequested: row => tab.previewRequested(row)
    }
}
