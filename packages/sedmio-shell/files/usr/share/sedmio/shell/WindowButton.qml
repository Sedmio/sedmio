import QtQuick
import Quickshell
import Quickshell.Widgets

// Программа на панели: все её окна в одной кнопке.
// Одно окно: клик — показать, по активному — свернуть, средняя кнопка —
// закрыть. Несколько: под значком точки по числу окон, клик — список
// окон рядом с панелью, в нём выбрать или закрыть.
// Закрытое окно исчезает раньше кнопки, отсюда ?. везде.
Item {
    id: root
    required property var windows
    required property var window
    required property Item tooltip

    readonly property var first: windows.length > 0 ? windows[0] : null
    readonly property bool single: windows.length === 1
    readonly property bool anyActive: windows.some(w => w?.activated)
    readonly property bool allMinimized: windows.length > 0 && windows.every(w => w?.minimized)

    // .desktop-файлы Quickshell читает в фоне: пересчитать, когда дочитал.
    readonly property var entry: DesktopEntries.applications.values.length >= 0
        ? DesktopEntries.heuristicLookup(first?.appId ?? "") : null
    readonly property string iconName: entry ? entry.icon : (first?.appId ?? "")
    readonly property string iconSource: Quickshell.iconPath(iconName, true) || Quickshell.iconPath("application-x-executable")

    function plural(n, one, few, many) {
        const n10 = n % 10, n100 = n % 100;
        if (n10 === 1 && n100 !== 11) return one;
        if (n10 >= 2 && n10 <= 4 && (n100 < 12 || n100 > 14)) return few;
        return many;
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
        active: root.anyActive || popup.visible
        tooltip: popup.visible ? null : root.tooltip
        hint: root.single ? (root.first?.title ?? "")
            : (root.entry?.name ?? root.first?.appId ?? "") + " · " + root.windows.length + " "
              + root.plural(root.windows.length, "окно", "окна", "окон")

        onClicked: event => {
            if (!root.first) return;
            if (!root.single) {
                if (event.button === Qt.LeftButton) {
                    if (root.tooltip) root.tooltip.hide();
                    popup.visible = !popup.visible;
                }
                return;
            }
            if (event.button === Qt.MiddleButton) {
                root.first.close();
            } else if (root.first.activated) {
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

        Rectangle {
            anchors.fill: parent
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
                             : rowArea.containsMouse ? Theme.paperDeep : "transparent"
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
                            color: closeArea.containsMouse ? Theme.terracottaSoft : "transparent"
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
