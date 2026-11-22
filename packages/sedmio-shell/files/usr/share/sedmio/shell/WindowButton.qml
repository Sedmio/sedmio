import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Sedmio.Style

// Программа на панели: все её окна в одной кнопке, как в Windows.
// Закреплённая и не запущенная — клик запускает. Одно окно: клик —
// показать, по активному — свернуть. Несколько: под значком точки по числу
// окон, клик — список окон рядом с панелью, в нём выбрать или закрыть.
// Средняя кнопка и Shift+щелчок — ещё одно окно программы. Правая — меню: запустить,
// закрепить или открепить, закрыть окна.
// В строку (док, панель задач) метка — под значком, список окон и меню —
// над кнопкой. С подписью (панель задач) у запущенной программы рядом со
// значком заголовок окна (окон несколько — название программы).
// Закрытое окно исчезает раньше кнопки, отсюда ?. везде.
Item {
    id: root
    required property var group
    required property var window
    required property Item tooltip
    property bool horizontal: false
    // Сторона кнопки (без подписи); задаёт панель.
    property real buttonSize: Theme.buttonSize
    property bool labeled: false

    readonly property var windows: group ? group.windows : []
    readonly property var first: windows.length > 0 ? windows[0] : null
    readonly property bool running: windows.length > 0
    readonly property bool single: windows.length === 1
    readonly property bool anyActive: windows.some(w => w?.activated)
    readonly property bool allMinimized: windows.length > 0 && windows.every(w => w?.minimized)

    readonly property var entry: group ? group.entry : null
    readonly property bool pinned: !!entry && PinnedApps.isPinned(entry.id)
    readonly property string iconName: entry ? entry.icon : (first?.appId ?? "")
    readonly property string iconSource: Icons.path(iconName, true) || Icons.path("application-x-executable")

    function plural(n, one, few, many) {
        const n10 = n % 10, n100 = n % 100;
        if (n10 === 1 && n100 !== 11) return one;
        if (n10 >= 2 && n10 <= 4 && (n100 < 12 || n100 > 14)) return few;
        return many;
    }

    function launch() {
        if (root.tooltip) root.tooltip.hide();
        ShellState.launchGroup(group);
    }

    readonly property bool showLabel: labeled && running
    readonly property string label: !running ? "" : single ? (first?.title ?? "")
        : (entry?.name ?? first?.appId ?? "")
    implicitWidth: showLabel ? 190 : buttonSize + 4
    implicitHeight: buttonSize + 4

    // Метка, как в Windows 11: запущена — короткая серая, активна — длинная
    // зелёная; только закреплена — метки нет. В полосе слева — сбоку от
    // кнопки; в доке и панели задач — внутри карточки у нижнего края, а у
    // программы с несколькими окнами её место занимают точки (ниже).
    Rectangle {
        readonly property real length: root.anyActive ? 20 : root.running ? 8 : 0
        visible: !root.horizontal || root.windows.length < 2
        z: 1
        x: root.horizontal ? (root.width - width) / 2 : 2
        y: root.horizontal ? button.y + button.height - height - 2 : (root.height - height) / 2
        width: root.horizontal ? length : 4
        height: root.horizontal ? 4 : length
        radius: 2
        color: root.anyActive ? Theme.green : Theme.inkMuted
        Behavior on width { enabled: root.horizontal; NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutBack } }
        Behavior on height { enabled: !root.horizontal; NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutBack } }
        Behavior on color { ColorAnimation { duration: Theme.animFast } }
    }

    BarButton {
        id: button
        anchors.centerIn: parent
        size: root.buttonSize
        implicitWidth: root.showLabel ? root.width - 4 : size
        active: root.anyActive || popup.visible || menu.visible
        tooltip: popup.visible || menu.visible || root.previewShown ? null : root.tooltip
        // У запущенной вместо подсказки — миниатюры (если они есть).
        hint: root.showLabel && root.single ? ""
            : root.running && previewLoader.item ? ""
            : !root.running ? (root.entry?.name ?? "")
            : root.single ? (root.first?.title ?? "")
            : (root.entry?.name ?? root.first?.appId ?? "") + " · " + root.windows.length + " "
              + root.plural(root.windows.length, "окно", "окна", "окон")

        onClicked: event => {
            root.hidePreview();
            if (event.button === Qt.RightButton) {
                if (root.tooltip) root.tooltip.hide();
                popup.visible = false;
                menu.visible = !menu.visible;
                return;
            }
            if (event.button === Qt.MiddleButton || !root.running
                || (event.modifiers & Qt.ShiftModifier)) {
                root.launch();
                return;
            }
            if (!root.single) {
                if (root.tooltip) root.tooltip.hide();
                menu.visible = false;
                popup.visible = !popup.visible;
                return;
            }
            if (root.first.activated) {
                root.updateRectangle();
                root.first.minimized = true;
            } else {
                root.first.activate();
            }
        }

        IconImage {
            id: icon
            anchors.centerIn: root.showLabel ? undefined : parent
            anchors.verticalCenter: root.showLabel ? parent.verticalCenter : undefined
            x: root.showLabel ? 6 : 0
            // Освобождает место отметке под значком: в доке — у любой
            // запущенной, иначе — у точек нескольких окон.
            anchors.verticalCenterOffset: (root.horizontal && !root.showLabel ? root.running
                                                                         : root.windows.length > 1) ? -3 : 0
            implicitSize: Math.round(root.buttonSize * 2 / 3)
            source: root.iconSource
            opacity: root.allMinimized ? 0.45 : 1
            Behavior on opacity { NumberAnimation { duration: Theme.animNormal } }
            Behavior on anchors.verticalCenterOffset { NumberAnimation { duration: Theme.animFast } }
        }

        SText {
            visible: root.showLabel
            anchors { left: icon.right; leftMargin: 8; right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
            elide: Text.ElideRight
            text: root.label
            size: 13
            weight: root.anyActive ? 600 : 450
            color: root.allMinimized ? Theme.inkMuted : Theme.ink
        }

        // Сколько окон: точки под значком (больше трёх — всё равно три).
        Row {
            anchors { horizontalCenter: icon.horizontalCenter; bottom: parent.bottom; bottomMargin: 2 }
            spacing: 3
            visible: !root.single
            Repeater {
                model: Math.min(root.windows.length, 3)
                Rectangle {
                    width: 4
                    height: 4
                    radius: 2
                    color: root.anyActive ? Theme.green : Theme.inkMuted
                }
            }
        }
    }

    // Список окон программы, справа от кнопки (над ней — в доке и на панели задач).
    PopupWindow {
        id: popup
        anchor.item: button
        anchor.rect.y: root.horizontal ? -10 : 0
        anchor.rect.width: root.horizontal ? button.width : button.width + 14
        anchor.rect.height: button.height
        anchor.edges: root.horizontal ? Edges.Top : Edges.Right
        anchor.gravity: root.horizontal ? Edges.Top : Edges.Right
        grabFocus: true
        color: "transparent"
        implicitWidth: 320
        implicitHeight: rows.implicitHeight + 12
        visible: false
        onVisibleChanged: if (visible) {
            listCard.forceActiveFocus();
            listPop.restart();
        }
        PopIn { id: listPop; card: listCard }
        BackgroundEffect.blurRegion: CardBlur { card: listCard }

        Rectangle {
            id: listCard
            anchors.fill: parent
            transformOrigin: root.horizontal ? Item.Bottom : Item.Left
            focus: true
            Keys.onEscapePressed: popup.visible = false
            radius: 12
            color: Qt.alpha(Theme.surface, Theme.glassOpacity ?? 1)
            border.width: 1
            border.color: Theme.line

            Column {
                id: rows
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 6 }
                spacing: 2

                Repeater {
                    model: root.windows

                    Rectangle {
                        id: row
                        required property var modelData
                        width: rows.width
                        height: 38
                        radius: 9
                        color: modelData?.activated ? Theme.greenWash
                             : rowArea.containsMouse ? Theme.paperDeep : Qt.alpha(Theme.paperDeep, 0)
                        Behavior on color { ColorAnimation { duration: Theme.animFast } }

                        MouseArea {
                            id: rowArea
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                            onClicked: event => {
                                if (!row.modelData) return;
                                if (event.button === Qt.MiddleButton) {
                                    row.modelData.close();
                                    return;
                                }
                                row.modelData.activate();
                                popup.visible = false;
                            }
                        }

                        IconImage {
                            id: rowIcon
                            anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                            implicitSize: 18
                            source: root.iconSource
                            opacity: row.modelData?.minimized ? 0.45 : 1
                        }
                        SText {
                            anchors {
                                left: rowIcon.right; leftMargin: 10
                                right: closeButton.left; rightMargin: 6
                                verticalCenter: parent.verticalCenter
                            }
                            elide: Text.ElideRight
                            size: 13
                            weight: row.modelData?.activated ? 600 : 400
                            color: row.modelData?.minimized ? Theme.inkMuted : Theme.ink
                            text: row.modelData?.title ?? ""
                        }
                        Rectangle {
                            id: closeButton
                            anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
                            width: 26
                            height: 26
                            radius: 7
                            visible: rowArea.containsMouse || closeArea.containsMouse
                            color: closeArea.containsMouse ? Theme.terracottaSoft : Qt.alpha(Theme.terracottaSoft, 0)
                            SText {
                                anchors.centerIn: parent
                                size: 12
                                color: closeArea.containsMouse ? Theme.terracotta : Theme.inkMuted
                                text: "✕"
                            }
                            MouseArea {
                                id: closeArea
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: row.modelData?.close()
                            }
                        }
                    }
                }
            }
        }
    }

    // Правый щелчок: запустить ещё окно, закрепить или открепить, закрыть.
    ContextMenu {
        id: menu
        anchor.item: button
        anchor.rect.y: root.horizontal ? -10 : 0
        anchor.rect.width: root.horizontal ? button.width : button.width + 14
        anchor.rect.height: button.height
        anchor.edges: root.horizontal ? Edges.Top : Edges.Right
        anchor.gravity: root.horizontal ? Edges.Top : Edges.Right
        items: {
            const list = [];
            if (root.entry) {
                list.push({ icon: root.entry.icon, text: root.entry.name, action: "launch" });
                list.push(root.pinned
                    ? { icon: "window-unpin", text: "Открепить от панели", action: "unpin" }
                    : { icon: "window-pin", text: "Закрепить на панели", action: "pin" });
            }
            if (root.running) {
                if (list.length > 0) list.push({ separator: true });
                list.push({ icon: "window-close", text: root.single ? "Закрыть окно" : "Закрыть все окна", action: "close" });
            }
            return list;
        }
        onTriggered: action => {
            switch (action) {
            case "launch": root.launch(); break;
            case "pin": PinnedApps.pin(root.entry.id); break;
            case "unpin": PinnedApps.unpin(root.entry.id); break;
            case "close": for (const w of root.windows.slice()) w?.close(); break;
            }
        }
    }

    // Окон стало меньше или больше, пока список открыт: KWin не перерисует
    // всплывающее окно нового размера, а сожмёт старую картинку — открываем
    // список заново. Осталось одно окно — список больше не нужен.
    property int shownCount: 0
    function reopenIfResized() {
        if (!popup.visible || windows.length === shownCount) return;
        popup.visible = false;
        // single тут может быть ещё старым — смотрим на длину.
        if (windows.length > 1) Qt.callLater(() => popup.visible = true);
    }
    Connections {
        target: popup
        function onVisibleChanged() {
            if (popup.visible) root.shownCount = root.windows.length;
            ShellState.panelMenus += popup.visible ? 1 : -1;
        }
    }
    Connections {
        target: menu
        function onVisibleChanged() { ShellState.panelMenus += menu.visible ? 1 : -1; }
    }
    Component.onDestruction: {
        ShellState.panelMenus -= (popup.visible ? 1 : 0) + (menu.visible ? 1 : 0) + (previewShown ? 1 : 0);
        if (ShellState.previewOwner === root) ShellState.previewOwner = null;
    }

    // ── Миниатюры окон при наведении ───────────────────────────────────
    // Через полсекунды наведения; если миниатюры уже открыты у соседней
    // кнопки — сразу. Уходят, когда указатель ушёл и с кнопки, и с них.
    readonly property Item barButton: button
    readonly property bool previewShown: previewLoader.item?.visible ?? false
    Loader {
        id: previewLoader
        onStatusChanged: if (status === Loader.Error) console.warn("Миниатюры окон недоступны")
        Component.onCompleted: setSource("WindowPreview.qml", { owner: root })
    }
    Connections {
        target: previewLoader.item
        function onHoveredChanged() {
            if (previewLoader.item.hovered) previewClose.stop();
            else previewClose.restart();
        }
        function onActivated() { root.hidePreview(); }
        // Пока открыты миниатюры, док не прячется (как с меню).
        function onVisibleChanged() { ShellState.panelMenus += previewLoader.item.visible ? 1 : -1; }
    }
    Connections {
        target: button
        function onHoveredChanged() {
            if (button.hovered) {
                previewClose.stop();
                if (!root.running) return;
                const other = ShellState.previewOwner;
                if (other && other !== root && other.previewShown) {
                    other.hidePreview();
                    root.showPreview();
                } else {
                    previewOpen.restart();
                }
            } else {
                previewOpen.stop();
                previewClose.restart();
            }
        }
    }
    Timer { id: previewOpen; interval: 450; onTriggered: root.showPreview() }
    Timer {
        id: previewClose
        interval: 300
        onTriggered: if (!button.hovered && !(previewLoader.item?.hovered ?? false)) root.hidePreview()
    }
    function showPreview() {
        if (!running || popup.visible || menu.visible || !previewLoader.item) return;
        if (root.tooltip) root.tooltip.hide();
        ShellState.previewOwner = root;
        previewLoader.item.place();
        previewLoader.item.visible = true;
    }
    function hidePreview() {
        previewOpen.stop();
        if (previewLoader.item) previewLoader.item.visible = false;
    }
    // Окон стало больше или меньше: всплывающее окно нового размера KWin
    // не перерисует (см. ниже) — показываем заново.
    function reopenPreview() {
        if (!previewShown) return;
        hidePreview();
        if (running) Qt.callLater(showPreview);
    }
    // Куда KWin сворачивает окна (анимация «в кнопку»).
    function updateRectangle() {
        const p = button.mapToItem(null, 0, 0);
        for (const w of windows) {
            if (w) w.setRectangle(window, Qt.rect(p.x, p.y, button.width, button.height));
        }
    }

    Component.onCompleted: updateRectangle()
    onXChanged: updateRectangle()
    onYChanged: updateRectangle()
    onWindowsChanged: { updateRectangle(); reopenIfResized(); reopenPreview(); }
}
