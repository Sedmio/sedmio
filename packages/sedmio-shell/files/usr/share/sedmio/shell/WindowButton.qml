import QtQuick
import Quickshell
import Quickshell.Widgets
import Sedmio.Style

// Программа на панели: все её окна в одной кнопке, как в Windows.
// Закреплённая и не запущенная — клик запускает. Одно окно: клик —
// показать, по активному — свернуть. Несколько: под значком точки по числу
// окон, клик — список окон рядом с панелью, в нём выбрать или закрыть.
// Средняя кнопка и Shift+щелчок — ещё одно окно программы. Правая — меню: запустить,
// закрепить или открепить, закрыть окна.
// Закрытое окно исчезает раньше кнопки, отсюда ?. везде.
Item {
    id: root
    required property var group
    required property var window
    required property Item tooltip

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

    height: Theme.buttonSize + 4

    // Метка активного окна на краю панели
    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        x: 2
        width: 4
        height: root.anyActive ? 20 : 0
        radius: 2
        color: Theme.green
        Behavior on height { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutBack } }
    }

    BarButton {
        id: button
        anchors.centerIn: parent
        active: root.anyActive || popup.visible || menu.visible
        tooltip: popup.visible || menu.visible ? null : root.tooltip
        hint: !root.running ? (root.entry?.name ?? "")
            : root.single ? (root.first?.title ?? "")
            : (root.entry?.name ?? root.first?.appId ?? "") + " · " + root.windows.length + " "
              + root.plural(root.windows.length, "окно", "окна", "окон")

        onClicked: event => {
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
            anchors.centerIn: parent
            anchors.verticalCenterOffset: root.single ? 0 : -3
            implicitSize: 24
            source: root.iconSource
            opacity: root.allMinimized ? 0.45 : 1
            Behavior on opacity { NumberAnimation { duration: Theme.animNormal } }
            Behavior on anchors.verticalCenterOffset { NumberAnimation { duration: Theme.animFast } }
        }

        // Сколько окон: точки под значком (больше трёх — всё равно три).
        Row {
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 3 }
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

    // Список окон программы, справа от кнопки.
    PopupWindow {
        id: popup
        anchor.item: button
        anchor.rect.width: button.width + 14
        anchor.rect.height: button.height
        anchor.edges: Edges.Right
        anchor.gravity: Edges.Right
        grabFocus: true
        color: "transparent"
        implicitWidth: 320
        implicitHeight: rows.implicitHeight + 12
        visible: false
        onVisibleChanged: if (visible) listCard.forceActiveFocus()

        Rectangle {
            id: listCard
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: popup.visible = false
            radius: 12
            color: Theme.surface
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
        anchor.rect.width: button.width + 14
        anchor.rect.height: button.height
        anchor.edges: Edges.Right
        anchor.gravity: Edges.Right
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
        function onVisibleChanged() { if (popup.visible) root.shownCount = root.windows.length; }
    }

    // Куда KWin сворачивает окна (анимация «в кнопку»).
    function updateRectangle() {
        const p = button.mapToItem(null, 0, 0);
        for (const w of windows) {
            if (w) w.setRectangle(window, Qt.rect(p.x, p.y, button.width, button.height));
        }
    }

    Component.onCompleted: updateRectangle()
    onYChanged: updateRectangle()
    onWindowsChanged: { updateRectangle(); reopenIfResized(); }
}
