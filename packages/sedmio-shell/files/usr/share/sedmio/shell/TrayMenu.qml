import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Sedmio.Style

// Меню значка в трее (dbusmenu программы) — своё, в стиле Sedmio, а не
// QMenu из виджетов Qt (для него Quickshell пришлось бы запускать в режиме
// QApplication). Пункты со значками, черты, флажки и переключатели,
// недоступные пункты, подменю — сбоку, по наведению или щелчку.
// Пункт выполнен — закрывается вся цепочка меню. Стрелки выбирают,
// Enter выполняет, → и ← открывают и закрывают подменю, Esc закрывает.
PopupWindow {
    id: menu
    // QsMenuHandle: меню значка или пункт с подменю.
    property var handle: null
    // Верхнее меню цепочки (у подменю — его меню значка).
    property var top: menu
    property var parentMenu: null

    function closeAll() {
        top.visible = false;
    }

    QsMenuOpener {
        id: opener
        menu: menu.handle
    }
    readonly property var entries: opener.children ? opener.children.values : []

    // Выбранная строка; -1 — никакой.
    property int current: -1
    // Строка, чьё подменю открыто; -1 — никакое.
    property int openSub: -1

    function step(direction) {
        const n = entries.length;
        let i = current < 0 ? (direction > 0 ? -1 : n) : current;
        for (let k = 0; k < n; k++) {
            i = (i + direction + n) % n;
            if (!entries[i].isSeparator && entries[i].enabled) { current = i; return; }
        }
    }
    function activate(index) {
        const entry = entries[index];
        if (!entry || entry.isSeparator || !entry.enabled) return;
        if (entry.hasChildren) {
            openSub = index;
            return;
        }
        entry.triggered();
        closeAll();
    }

    // Пункты приходят по D-Bus не сразу. Всплывающее окно другого размера
    // KWin не перерисует, а сожмёт старую картинку, — поэтому показываем,
    // когда пункты пришли (не дольше полсекунды), а сменилось их число —
    // открываем заново.
    property bool pending: false
    property int shownCount: 0
    function open() {
        current = -1;
        openSub = -1;
        if (entries.length > 0) show();
        else {
            pending = true;
            pendingTimer.restart();
        }
    }
    function show() {
        pending = false;
        pendingTimer.stop();
        shownCount = entries.length;
        visible = true;
    }
    // Пункты так и не пришли — пустое меню не показываем.
    Timer {
        id: pendingTimer
        interval: 500
        onTriggered: {
            if (!menu.pending) return;
            menu.pending = false;
            if (menu.entries.length > 0) menu.show();
        }
    }
    onEntriesChanged: {
        if (pending && entries.length > 0) Qt.callLater(show);
        else if (visible && entries.length !== shownCount) {
            visible = false;
            if (entries.length > 0) Qt.callLater(open);
        }
    }

    grabFocus: true
    color: "transparent"
    implicitWidth: 280
    implicitHeight: Math.max(rows.implicitHeight + 12, 24)
    visible: false

    onVisibleChanged: {
        if (visible) {
            card.forceActiveFocus();
            pop.restart();
        } else {
            openSub = -1;
            // Подменю закрылось само (Esc, ←) — можно открыть снова.
            if (parentMenu && parentMenu.openSub >= 0) parentMenu.openSub = -1;
        }
    }
    PopIn { id: pop; card: card }
    BackgroundEffect.blurRegion: CardBlur { card: card }

    Rectangle {
        id: card
        anchors.fill: parent
        transformOrigin: menu.parentMenu ? Item.Left
            : (menu.anchor.gravity & Edges.Top) ? Item.Bottom
            : (menu.anchor.gravity & Edges.Bottom) ? Item.Top : Item.Left
        radius: 12
        color: Qt.alpha(Theme.surface, Theme.glassOpacity ?? 1)
        border.width: 1
        border.color: Theme.line
        focus: true

        Keys.onPressed: event => {
            switch (event.key) {
            case Qt.Key_Escape: menu.visible = false; break;
            case Qt.Key_Down: case Qt.Key_Tab: menu.step(1); break;
            case Qt.Key_Up: case Qt.Key_Backtab: menu.step(-1); break;
            case Qt.Key_Right:
                if (menu.current >= 0 && menu.entries[menu.current]?.hasChildren) menu.openSub = menu.current;
                break;
            case Qt.Key_Left: if (menu.parentMenu) menu.visible = false; break;
            case Qt.Key_Return: case Qt.Key_Enter: case Qt.Key_Space: menu.activate(menu.current); break;
            default: return;
            }
            event.accepted = true;
        }

        Column {
            id: rows
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 6 }
            spacing: 2

            Repeater {
                model: menu.entries

                Item {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool checkable: modelData.buttonType !== QsMenuButtonType.None
                    readonly property bool checked: modelData.checkState === Qt.Checked
                    width: rows.width
                    height: modelData.isSeparator ? 9 : 34

                    Rectangle {
                        visible: row.modelData.isSeparator
                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 8 }
                        height: 1
                        color: Theme.line
                    }

                    Rectangle {
                        visible: !row.modelData.isSeparator
                        anchors.fill: parent
                        radius: 8
                        opacity: row.modelData.enabled ? 1 : 0.45
                        color: (menu.current === row.index || menu.openSub === row.index) && row.modelData.enabled
                            ? Theme.paperDeep : Qt.alpha(Theme.paperDeep, 0)
                        Behavior on color { ColorAnimation { duration: Theme.animFast } }

                        // Флажок или переключатель — на месте значка.
                        Rectangle {
                            id: check
                            visible: row.checkable
                            anchors { left: parent.left; leftMargin: 11; verticalCenter: parent.verticalCenter }
                            width: 16
                            height: 16
                            radius: row.modelData.buttonType === QsMenuButtonType.RadioButton ? 8 : 4
                            color: row.checked ? Theme.green : "transparent"
                            border.width: row.checked ? 0 : 1.5
                            border.color: Theme.inkMuted
                            SText {
                                anchors.centerIn: parent
                                visible: row.checked && row.modelData.buttonType !== QsMenuButtonType.RadioButton
                                size: 11
                                weight: 700
                                color: Theme.textOnGreen
                                text: "✓"
                            }
                            Rectangle {
                                anchors.centerIn: parent
                                visible: row.checked && row.modelData.buttonType === QsMenuButtonType.RadioButton
                                width: 6
                                height: 6
                                radius: 3
                                color: Theme.textOnGreen
                            }
                        }
                        IconImage {
                            id: rowIcon
                            visible: !row.checkable
                            anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                            implicitSize: 18
                            source: row.modelData.icon || ""
                        }
                        SText {
                            anchors {
                                left: parent.left; leftMargin: 38
                                right: arrow.left; rightMargin: 6
                                verticalCenter: parent.verticalCenter
                            }
                            elide: Text.ElideRight
                            size: 13
                            // Подчёркивание перед буквой — клавиша-ускоритель
                            // dbusmenu («_Открыть»), «__» — само подчёркивание.
                            text: (row.modelData.text || "").replace(/_(_?)/g, "$1")
                        }
                        SText {
                            id: arrow
                            anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                            visible: row.modelData.hasChildren
                            size: 12
                            color: Theme.inkMuted
                            text: "›"
                        }
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onContainsMouseChanged: {
                                if (!containsMouse) return;
                                menu.current = row.index;
                                subTimer.restart();
                            }
                            onClicked: menu.activate(row.index)
                        }

                        // Подменю: справа от строки, у края экрана — слева.
                        Loader {
                            active: menu.openSub === row.index && row.modelData.hasChildren
                            onLoaded: {
                                item.anchor.item = parent;
                                item.anchor.rect.x = -8;
                                item.anchor.rect.y = -6;
                                item.anchor.rect.width = parent.width + 16;
                                item.anchor.edges = Edges.Top | Edges.Right;
                                item.anchor.gravity = Edges.Bottom | Edges.Right;
                                item.anchor.adjustment = PopupAdjustment.FlipX | PopupAdjustment.SlideY;
                                item.handle = row.modelData;
                                item.top = menu.top;
                                item.parentMenu = menu;
                                item.open();
                            }
                            source: "TrayMenu.qml"
                        }
                    }
                }
            }
        }
    }

    // Наведение на строку: через 200 мс открыть её подменю (или закрыть чужое).
    Timer {
        id: subTimer
        interval: 200
        onTriggered: {
            const entry = menu.entries[menu.current];
            menu.openSub = entry?.hasChildren && entry.enabled ? menu.current : -1;
        }
    }
}
