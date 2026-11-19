import QtQuick
import Quickshell
import Quickshell.Widgets
import Sedmio.Style

// Содержимое запуска программ: поле поиска и список. Подложку рисует
// DrawerShape в слое рамки, здесь только то, что на ней.
Item {
    id: root
    property bool open: false
    signal closeRequested(bool restoreFocus)

    property var results: []

    // Сколько места нужно: поле и столько строк, сколько найдено
    // (но не меньше трёх, чтобы панель не прыгала на каждой букве).
    property real maxHeight: 600
    readonly property real wantedHeight: Math.min(maxHeight,
        field.height + 10 + Math.max(3, list.count) * (54 + list.spacing))

    function refresh() {
        results = AppSearch.search(search.text);
        list.currentIndex = 0;
        list.positionViewAtBeginning();
    }

    function launchCurrent(inTerminal) {
        const entry = results[list.currentIndex];
        if (!entry) return;
        AppSearch.launch(entry, inTerminal === true);
        root.closeRequested(false);
    }

    // Правый щелчок по программе — закрепить на панели или открепить,
    // как в «Пуске» Windows. У строк «Выполнить» меню нет.
    property var menuEntry: null
    // Клавиша Menu или Shift+F10 — меню выбранной программы.
    function showMenuForCurrent() {
        const item = list.currentItem;
        if (!item) return;
        showMenu(item, 40, item.height - 6);
        appMenu.current = 0;
    }

    function showMenu(item, x, y) {
        const entry = item.modelData;
        if (!entry || entry.run || !entry.id) return;
        menuEntry = entry;
        appMenu.anchor.item = item;
        appMenu.anchor.rect.x = x;
        appMenu.anchor.rect.y = y;
        appMenu.visible = true;
    }

    ContextMenu {
        id: appMenu
        anchor.rect.width: 1
        anchor.rect.height: 1
        anchor.edges: Edges.Bottom | Edges.Right
        anchor.gravity: Edges.Bottom | Edges.Right
        items: {
            const entry = root.menuEntry;
            if (!entry) return [];
            return [
                { icon: entry.icon, text: "Открыть", action: "launch" },
                PinnedApps.isPinned(entry.id)
                    ? { icon: "window-unpin", text: "Открепить от панели", action: "unpin" }
                    : { icon: "window-pin", text: "Закрепить на панели", action: "pin" },
            ];
        }
        onTriggered: action => {
            const entry = root.menuEntry;
            if (!entry) return;
            if (action === "launch") {
                AppSearch.launch(entry, false);
                root.closeRequested(false);
            } else if (action === "pin") {
                PinnedApps.pin(entry.id);
            } else if (action === "unpin") {
                PinnedApps.unpin(entry.id);
            }
            search.forceActiveFocus();
        }
        onVisibleChanged: if (!visible) search.forceActiveFocus()
    }

    onOpenChanged: {
        if (!open) appMenu.visible = false;
        if (open) {
            search.text = "";
            refresh();
            AppSearch.rescan();
            search.forceActiveFocus();
        }
    }

    // Список программ дочитывается в фоне — обновить, если открыт.
    Connections {
        target: DesktopEntries.applications
        function onValuesChanged() { if (root.open) root.refresh(); }
    }
    Connections {
        target: AppSearch
        // Не сбивать выбор, если по списку уже пошли стрелками.
        function onExecutablesChanged() { if (root.open && search.text !== "" && list.currentIndex === 0) root.refresh(); }
    }

    // Поле поиска
    Rectangle {
        id: field
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: 50
        radius: 14
        color: Theme.surface
        border.color: search.activeFocus ? Theme.lineStrong : Theme.line
        border.width: 1

        IconImage {
            id: searchIcon
            anchors.verticalCenter: parent.verticalCenter
            x: 16
            implicitSize: 20
            source: Icons.path("search")
            opacity: 0.7
        }

        TextInput {
            id: search
            anchors { left: searchIcon.right; leftMargin: 12; right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
            font.family: Theme.fontFamily
            font.pixelSize: 16
            font.variableAxes: ({ "wght": 450 })
            color: Theme.ink
            selectionColor: Theme.greenWash
            selectedTextColor: Theme.ink
            clip: true

            onTextChanged: root.refresh()

            Keys.onPressed: event => {
                switch (event.key) {
                case Qt.Key_Escape:
                    root.closeRequested(true);
                    break;
                case Qt.Key_Return:
                case Qt.Key_Enter:
                    root.launchCurrent((event.modifiers & Qt.ControlModifier) !== 0);
                    break;
                case Qt.Key_Down:
                case Qt.Key_Tab:
                    list.incrementCurrentIndex();
                    break;
                case Qt.Key_Up:
                case Qt.Key_Backtab:
                    list.decrementCurrentIndex();
                    break;
                case Qt.Key_PageDown:
                    list.currentIndex = Math.min(list.count - 1, list.currentIndex + 7);
                    break;
                case Qt.Key_PageUp:
                    list.currentIndex = Math.max(0, list.currentIndex - 7);
                    break;
                case Qt.Key_Menu:
                    root.showMenuForCurrent();
                    break;
                case Qt.Key_F10:
                    if (!(event.modifiers & Qt.ShiftModifier)) return;
                    root.showMenuForCurrent();
                    break;
                default:
                    return;
                }
                event.accepted = true;
            }

            SText {
                anchors.verticalCenter: parent.verticalCenter
                visible: search.text === ""
                text: "Найти программу"
                color: Theme.inkMuted
                size: 16
            }
        }
    }

    ListView {
        id: list
        anchors { top: field.bottom; topMargin: 10; left: parent.left; right: parent.right; bottom: parent.bottom }
        clip: true
        spacing: 2
        model: root.results
        boundsBehavior: Flickable.StopAtBounds
        highlightMoveDuration: Theme.animFast
        highlightMoveVelocity: -1
        keyNavigationWraps: true

        highlight: Rectangle {
            radius: Theme.radius
            color: Theme.greenWash
        }

        delegate: Item {
            id: row
            required property var modelData
            required property int index
            width: ListView.view.width
            height: 54

            Rectangle {
                anchors.fill: parent
                radius: Theme.radius
                color: Theme.paperDeep
                visible: mouse.containsMouse && list.currentIndex !== row.index
            }

            IconImage {
                id: icon
                anchors.verticalCenter: parent.verticalCenter
                x: 12
                implicitSize: 32
                source: Icons.path(row.modelData.icon, true) || Icons.path("application-x-executable")
            }

            Column {
                anchors { left: icon.right; leftMargin: 14; right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                spacing: 1

                SText {
                    width: parent.width
                    elide: Text.ElideRight
                    text: row.modelData.name
                    size: 15
                    weight: 550
                }
                SText {
                    readonly property string about: row.modelData.genericName || row.modelData.comment
                    width: parent.width
                    visible: about !== "" && about !== row.modelData.name
                    elide: Text.ElideRight
                    text: about
                    size: Theme.fontSmall
                    color: Theme.inkMuted
                }
            }

            MouseArea {
                id: mouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: event => {
                    list.currentIndex = row.index;
                    if (event.button === Qt.RightButton) root.showMenu(row, event.x, event.y);
                    else root.launchCurrent();
                }
            }
        }

        SText {
            anchors.centerIn: parent
            visible: list.count === 0
            text: "Ничего не нашлось"
            color: Theme.inkMuted
        }
    }
}
