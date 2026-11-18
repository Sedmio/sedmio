import QtQuick
import QtQuick.Controls
import Sedmio.Files

// Содержимое папки: плитки (grid) или таблица (list). Выделение мышью —
// как в проводнике Windows: клик, Ctrl — добавить или убрать, Shift —
// диапазон; стрелки, Home/End, PageUp/PageDown; набор букв — перейти к
// файлу с таким началом имени. Перетаскивание — наружу (в другие
// программы) и внутрь (на папку или на пустое место).
FocusScope {
    id: root
    required property FolderModel folder
    property string mode: "grid"
    // Строка, которую сейчас переименовывают, или -1.
    property int renamingRow: -1

    signal openRequested(int row)
    // row -1 — щёлкнули по пустому месту.
    signal contextMenuRequested(int row, Item item, real x, real y)
    signal dropRequested(var urls, url destination, var drop)
    signal renameFailed(string message)
    signal renamed(string newName)

    readonly property Item view: loader.item
    readonly property int currentRow: view ? view.currentIndex : -1

    function focusRow(row) {
        if (!view || row < 0) return;
        view.currentIndex = row;
        view.positionViewAtIndex(row, ItemView.Contain);
    }

    function startRename(row) {
        if (row < 0) return;
        focusRow(row);
        renamingRow = row;
    }

    function finishRename(row, text) {
        // Поле теряет фокус и при перестройке списка: считаем только
        // настоящее окончание правки той строки, что сейчас правится.
        if (row < 0 || row !== renamingRow) return;
        renamingRow = -1;
        root.forceActiveFocus();
        const message = FileOps.rename(folder.urlAt(row), text);
        if (message !== "") root.renameFailed(message);
        else root.renamed(text.trim());
    }

    onModeChanged: Qt.callLater(() => focusRow(Math.max(0, folder.firstSelected())))

    // Сколько плиток в ряду — для стрелок вверх и вниз.
    readonly property int columns: mode === "grid" && view ? Math.max(1, Math.floor(view.width / view.cellWidth)) : 1

    // Набор букв подряд — переход к файлу.
    property string typed: ""
    Timer {
        id: typedTimer
        interval: 900
        onTriggered: root.typed = ""
    }

    function moveTo(row, modifiers) {
        row = Math.max(0, Math.min(folder.count - 1, row));
        if (row < 0) return;
        if (modifiers & Qt.ShiftModifier) folder.select(row, 2);
        else if (!(modifiers & Qt.ControlModifier)) folder.select(row, 0);
        focusRow(row);
    }

    Keys.onPressed: event => {
        if (!view || renamingRow >= 0) return;
        const current = view.currentIndex;
        const page = mode === "grid" ? columns * Math.max(1, Math.floor(view.height / view.cellHeight))
                                     : Math.max(1, Math.floor(view.height / 34));
        switch (event.key) {
        case Qt.Key_Left:
            if (mode === "grid") moveTo(current - 1, event.modifiers); else return;
            break;
        case Qt.Key_Right:
            if (mode === "grid") moveTo(current + 1, event.modifiers); else return;
            break;
        case Qt.Key_Up: moveTo(current < 0 ? 0 : current - columns, event.modifiers); break;
        case Qt.Key_Down: moveTo(current < 0 ? 0 : current + columns, event.modifiers); break;
        case Qt.Key_Home: moveTo(0, event.modifiers); break;
        case Qt.Key_End: moveTo(folder.count - 1, event.modifiers); break;
        case Qt.Key_PageUp: moveTo(current - page, event.modifiers); break;
        case Qt.Key_PageDown: moveTo(current + page, event.modifiers); break;
        case Qt.Key_Space:
            if (event.modifiers & Qt.ControlModifier) folder.select(current, 1);
            else return;
            break;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            if (current >= 0) root.openRequested(current);
            break;
        case Qt.Key_Menu:
            if (current >= 0) {
                const item = view.itemAtIndex(current);
                if (item) root.contextMenuRequested(current, item, item.width / 2, item.height / 2);
            }
            break;
        default:
            if (event.text === "" || event.modifiers & (Qt.ControlModifier | Qt.AltModifier)
                || event.text.charCodeAt(0) < 32)
                return;
            typed += event.text.toLowerCase();
            typedTimer.restart();
            for (let row = 0; row < folder.count; ++row) {
                if (folder.nameAt(row).toLowerCase().startsWith(typed)) {
                    moveTo(row, 0);
                    break;
                }
            }
        }
        event.accepted = true;
    }

    // Что тащим: адреса выделенного.
    Item {
        id: dragGhost
        property var urls: []
        Drag.dragType: Drag.Automatic
        Drag.supportedActions: Qt.CopyAction | Qt.MoveAction | Qt.LinkAction
        Drag.proposedAction: Qt.MoveAction
        Drag.mimeData: ({ "text/uri-list": urls.map(u => u.toString()).join("\r\n") })
        Drag.onDragFinished: Drag.active = false
    }

    function startDrag() {
        dragGhost.urls = folder.selectedUrls();
        if (dragGhost.urls.length > 0) dragGhost.Drag.active = true;
    }

    // Общая логика нажатия на файл (плитку или строку).
    function pressed(row, mouse) {
        root.forceActiveFocus();
        if (renamingRow >= 0 && renamingRow !== row) renamingRow = -1;
        if (mouse.button === Qt.RightButton) {
            if (!folder.isSelected(row)) folder.select(row, 0);
            focusRow(row);
            return;
        }
        if (mouse.modifiers & Qt.ShiftModifier) folder.select(row, 2);
        else if (mouse.modifiers & Qt.ControlModifier) folder.select(row, 1);
        else if (!folder.isSelected(row)) folder.select(row, 0);
        view.currentIndex = row;
    }

    // Отпустили без перетаскивания: из нескольких выбранных остаётся одна.
    function released(row, mouse) {
        if (mouse.button === Qt.LeftButton && !(mouse.modifiers & (Qt.ShiftModifier | Qt.ControlModifier))
            && folder.selectedCount > 1)
            folder.select(row, 0);
    }

    function isCut(url) {
        const s = url.toString();
        return FileOps.cutUrls.some(u => u.toString() === s);
    }

    // Перетащили на папку или на пустое место
    function handleDrop(drop, destination) {
        if (!drop.hasUrls) return;
        const fromUs = drop.source === dragGhost;
        drop.accept(Qt.CopyAction);
        root.dropRequested(drop.urls, destination, { fromUs: fromUs, copy: fromUs && drop.proposedAction === Qt.CopyAction });
    }

    Loader {
        id: loader
        anchors.fill: parent
        sourceComponent: root.mode === "grid" ? gridComponent : listComponent
        focus: true
    }

    // Пусто, ничего не нашлось или папку не открыть
    Column {
        anchors.centerIn: parent
        spacing: 10
        visible: folder.count === 0 && !folder.loading

        SIcon {
            anchors.horizontalCenter: parent.horizontalCenter
            size: 56
            name: folder.error !== "" ? "dialog-warning" : folder.filter !== "" ? "edit-find" : "folder-open"
            opacity: 0.4
        }
        SText {
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(implicitWidth, root.width - 60)
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: folder.error !== "" ? folder.error
                : folder.filter !== "" ? "Ничего не нашлось"
                : folder.isTrash ? "Корзина пуста" : "Папка пуста"
            color: Theme.inkMuted
        }
    }

    // ---- Фон: клик по пустому месту, бросок файлов в эту папку

    component Background: MouseArea {
        id: bg
        z: -1
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: mouse => {
            root.forceActiveFocus();
            root.renamingRow = -1;
            if (!(mouse.modifiers & (Qt.ControlModifier | Qt.ShiftModifier))) folder.clearSelection();
            if (mouse.button === Qt.RightButton) root.contextMenuRequested(-1, bg, mouse.x, mouse.y);
        }
        DropArea {
            anchors.fill: parent
            keys: ["text/uri-list"]
            onDropped: drop => root.handleDrop(drop, folder.url)
        }
    }

    // ---- Плитки

    Component {
        id: gridComponent

        GridView {
            id: grid
            clip: true
            focus: true
            boundsBehavior: Flickable.StopAtBounds
            readonly property int minCell: 112
            cellWidth: Math.floor(width / Math.max(1, Math.floor(width / minCell)))
            cellHeight: 122
            topMargin: 8
            bottomMargin: 8
            model: root.folder
            currentIndex: -1
            keyNavigationEnabled: false
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            Background {
                width: grid.width
                height: Math.max(grid.height, grid.contentHeight + 16)
                y: -grid.topMargin
            }

            delegate: Item {
                id: cell
                required property int index
                required property string name
                required property url url
                required property string iconName
                required property string mimeType
                required property bool canPreview
                required property bool isDir
                required property bool isHidden
                required property bool selected

                width: grid.cellWidth
                height: grid.cellHeight

                Rectangle {
                    anchors { fill: parent; margins: 3 }
                    radius: 10
                    color: cell.selected ? Theme.greenSelect
                         : dropHere.containsDrag ? Theme.greenWash
                         : area.containsMouse ? Theme.paperDeep : "transparent"
                    border.width: grid.currentIndex === cell.index && root.activeFocus && !cell.selected ? 1 : 0
                    border.color: Theme.lineStrong
                }

                FileIcon {
                    id: icon
                    anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 10 }
                    size: 60
                    iconName: cell.iconName
                    url: cell.url
                    mimeType: cell.mimeType
                    canPreview: cell.canPreview
                    dimmed: cell.isHidden || root.isCut(cell.url)
                }

                SText {
                    anchors { top: icon.bottom; topMargin: 6; left: parent.left; right: parent.right; leftMargin: 8; rightMargin: 8 }
                    visible: root.renamingRow !== cell.index
                    text: cell.name
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    size: 13
                    lineHeight: 1.05
                }

                MouseArea {
                    id: area
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    drag.target: dragGhost
                    drag.threshold: 8
                    onPressed: mouse => root.pressed(cell.index, mouse)
                    onReleased: mouse => { if (!drag.active) root.released(cell.index, mouse); }
                    onClicked: mouse => {
                        if (mouse.button === Qt.RightButton) root.contextMenuRequested(cell.index, cell, mouse.x, mouse.y);
                    }
                    onDoubleClicked: mouse => { if (mouse.button === Qt.LeftButton) root.openRequested(cell.index); }
                    drag.onActiveChanged: if (drag.active) root.startDrag()
                }

                DropArea {
                    id: dropHere
                    anchors.fill: parent
                    enabled: cell.isDir && !cell.selected
                    keys: ["text/uri-list"]
                    onDropped: drop => root.handleDrop(drop, cell.url)
                }

                RenameField {
                    anchors { top: icon.bottom; topMargin: 4; horizontalCenter: parent.horizontalCenter }
                    width: parent.width + 24
                    row: cell.index
                    originalName: cell.name
                    isDir: cell.isDir
                    horizontalAlignment: TextInput.AlignHCenter
                }
            }
        }
    }

    // ---- Таблица

    Component {
        id: listComponent

        ListView {
            id: list
            clip: true
            focus: true
            boundsBehavior: Flickable.StopAtBounds
            model: root.folder
            currentIndex: -1
            keyNavigationEnabled: false
            headerPositioning: ListView.OverlayHeader
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            readonly property real dateWidth: 150
            readonly property real typeWidth: Math.min(180, width * 0.2)
            readonly property real sizeWidth: 124
            readonly property real cellHeight: 34

            Background {
                width: list.width
                height: Math.max(list.height, list.contentHeight)
                y: -list.headerItem?.height ?? 0
            }

            header: Rectangle {
                z: 2
                width: list.width
                height: 32
                color: Theme.surface

                component Column_: Item {
                    id: col
                    property string label
                    property string key
                    property real colWidth
                    width: colWidth
                    height: parent.height
                    SText {
                        anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                        text: col.label + (root.folder.sortBy === col.key ? (root.folder.descending ? " ↓" : " ↑") : "")
                        size: Theme.fontSmall
                        weight: 600
                        color: root.folder.sortBy === col.key ? Theme.ink : Theme.inkMuted
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            if (root.folder.sortBy === col.key) root.folder.descending = !root.folder.descending;
                            else {
                                root.folder.sortBy = col.key;
                                root.folder.descending = col.key === "date" || col.key === "size";
                            }
                        }
                    }
                }

                Row {
                    anchors { fill: parent; leftMargin: 34 }
                    Column_ { label: "Имя"; key: "name"; colWidth: list.width - 34 - list.dateWidth - list.typeWidth - list.sizeWidth }
                    Column_ { label: "Изменён"; key: "date"; colWidth: list.dateWidth }
                    Column_ { label: "Тип"; key: "type"; colWidth: list.typeWidth }
                    Column_ { label: "Размер"; key: "size"; colWidth: list.sizeWidth }
                }

                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: 1
                    color: Theme.line
                }
            }

            delegate: Item {
                id: line
                required property int index
                required property string name
                required property url url
                required property string iconName
                required property string mimeType
                required property bool isDir
                required property bool isHidden
                required property bool selected
                required property real size
                required property var modified
                required property string typeText
                required property int childCount

                width: list.width
                height: list.cellHeight

                Rectangle {
                    anchors { fill: parent; topMargin: 1; bottomMargin: 1 }
                    radius: 8
                    color: line.selected ? Theme.greenSelect
                         : dropHere.containsDrag ? Theme.greenWash
                         : area.containsMouse ? Theme.paperDeep : "transparent"
                    border.width: list.currentIndex === line.index && root.activeFocus && !line.selected ? 1 : 0
                    border.color: Theme.lineStrong
                }

                SIcon {
                    id: icon
                    anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                    size: 22
                    name: line.iconName
                    opacity: line.isHidden || root.isCut(line.url) ? 0.5 : 1
                }

                Row {
                    anchors { left: icon.right; leftMargin: 6; right: parent.right; verticalCenter: parent.verticalCenter }

                    SText {
                        width: list.width - 34 - list.dateWidth - list.typeWidth - list.sizeWidth
                        leftPadding: 8
                        rightPadding: 8
                        text: line.name
                        elide: Text.ElideMiddle
                        opacity: root.renamingRow === line.index ? 0 : 1
                    }
                    SText {
                        width: list.dateWidth
                        leftPadding: 8
                        text: Format.date(line.modified)
                        size: 13
                        color: Theme.inkSoft
                        elide: Text.ElideRight
                    }
                    SText {
                        width: list.typeWidth
                        leftPadding: 8
                        text: line.typeText
                        size: 13
                        color: Theme.inkSoft
                        elide: Text.ElideRight
                    }
                    SText {
                        width: list.sizeWidth
                        leftPadding: 8
                        text: line.isDir ? (line.childCount >= 0 ? Format.items(line.childCount) : "")
                                         : FileOps.formatSize(line.size)
                        size: 13
                        color: Theme.inkSoft
                        elide: Text.ElideRight
                    }
                }

                MouseArea {
                    id: area
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    drag.target: dragGhost
                    drag.threshold: 8
                    onPressed: mouse => root.pressed(line.index, mouse)
                    onReleased: mouse => { if (!drag.active) root.released(line.index, mouse); }
                    onClicked: mouse => {
                        if (mouse.button === Qt.RightButton) root.contextMenuRequested(line.index, line, mouse.x, mouse.y);
                    }
                    onDoubleClicked: mouse => { if (mouse.button === Qt.LeftButton) root.openRequested(line.index); }
                    drag.onActiveChanged: if (drag.active) root.startDrag()
                }

                DropArea {
                    id: dropHere
                    anchors.fill: parent
                    enabled: line.isDir && !line.selected
                    keys: ["text/uri-list"]
                    onDropped: drop => root.handleDrop(drop, line.url)
                }

                RenameField {
                    anchors { left: icon.right; leftMargin: 6; verticalCenter: parent.verticalCenter }
                    width: Math.min(420, list.width - 34 - list.dateWidth - list.typeWidth - list.sizeWidth)
                    row: line.index
                    originalName: line.name
                    isDir: line.isDir
                }
            }
        }
    }

    // ---- Переименование на месте

    component RenameField: TextField {
        id: field
        property int row
        property string originalName
        property bool isDir

        font.family: Theme.fontFamily
        font.pixelSize: 13
        color: Theme.ink
        selectionColor: Theme.greenSelect
        selectedTextColor: Theme.ink
        padding: 4
        leftPadding: 6
        rightPadding: 6
        z: 3
        background: Rectangle {
            radius: 6
            color: Theme.surface
            border.width: 1
            border.color: Theme.green
        }

        // У удаляемых строк index становится -1, как и renamingRow без правки.
        readonly property bool editing: row >= 0 && root.renamingRow === row

        visible: editing

        onEditingChanged: {
            if (!editing) return;
            text = originalName;
            forceActiveFocus();
            // Имя без расширения, как в проводнике: «отпуск».jpg
            const dot = isDir ? -1 : originalName.lastIndexOf(".");
            select(0, dot > 0 ? dot : originalName.length);
        }
        // Не onAccepted: TextInput отдаёт Enter дальше, и список открыл бы файл.
        Keys.onReturnPressed: event => { event.accepted = true; if (editing) root.finishRename(row, text); }
        Keys.onEnterPressed: event => { event.accepted = true; if (editing) root.finishRename(row, text); }
        onActiveFocusChanged: if (!activeFocus && editing) root.finishRename(row, text)
        Keys.onEscapePressed: {
            root.renamingRow = -1;
            root.forceActiveFocus();
        }
    }
}
