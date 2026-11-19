import QtQuick
import QtQuick.Layouts
import Quickshell
import Sedmio.Style

// Панель слева, часть рамки. Сверху знак Sedmio и открытые окна,
// снизу трей и кнопки состояния (раскладка, сеть, батарея, яркость, звук,
// уведомления, часы) — их порядок меняется
// перетаскиванием (BarOrder).
Item {
    id: bar
    required property var window     // окно рамки: меню трея, сворачивание
    required property string screenName
    required property Item tooltip

    // Правый щелчок по пустому месту панели — меню, как у панели задач
    // Windows. Под кнопками: их щелчки до него не доходят.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        onClicked: event => {
            const p = mapToItem(null, event.x, event.y);
            barMenu.anchor.rect.x = p.x;
            barMenu.anchor.rect.y = p.y;
            barMenu.visible = true;
        }
    }

    ContextMenu {
        id: barMenu
        anchor.window: bar.window
        anchor.rect.width: 1
        anchor.rect.height: 1
        anchor.edges: Edges.Bottom | Edges.Right
        anchor.gravity: Edges.Bottom | Edges.Right
        items: [
            { icon: "utilities-system-monitor", text: "Диспетчер задач", action: "tasks" },
            { icon: "user-desktop", text: "Показать рабочий стол", action: "desktop" },
            { separator: true },
            { icon: "preferences-system", text: "Параметры", action: "settings" },
        ]
        onTriggered: action => {
            ShellState.closeAll(false);
            if (action === "tasks") ShellState.launch("sedmio-tasks", ["sedmio-tasks"]);
            else if (action === "settings") ShellState.launch("", ["/usr/lib/sedmio/open-settings"]);
            else if (action === "desktop") Quickshell.execDetached(["busctl", "--user", "call", "org.kde.kglobalaccel",
                "/component/kwin", "org.kde.kglobalaccel.Component", "invokeShortcut", "s", "Show Desktop"]);
        }
    }

    ColumnLayout {
        id: topGroup
        anchors { top: parent.top; left: parent.left; right: parent.right; topMargin: Theme.border + 4 }
        spacing: 8

        LauncherButton {
            Layout.alignment: Qt.AlignHCenter
            screenName: bar.screenName
            tooltip: bar.tooltip
        }

        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: 22
            implicitHeight: 2
            radius: 1
            color: Theme.line
        }
    }

    WindowList {
        anchors {
            top: topGroup.bottom; topMargin: 8
            bottom: bottomGroup.top; bottomMargin: 8
            left: parent.left; right: parent.right
        }
        window: bar.window
        tooltip: bar.tooltip
    }

    ColumnLayout {
        id: bottomGroup
        anchors { bottom: parent.bottom; left: parent.left; right: parent.right; bottomMargin: Theme.border }
        spacing: 6

        Tray {
            Layout.alignment: Qt.AlignHCenter
            window: bar.window
            tooltip: bar.tooltip
        }

        // Кнопки в порядке из BarOrder. Зажать и потянуть — кнопка встаёт
        // на место той, над которой её держат; отпустили — порядок
        // сохраняется.
        ListView {
            id: buttons
            Layout.fillWidth: true
            Layout.preferredHeight: contentHeight
            interactive: false
            model: order

            ListModel { id: order }
            function sync() {
                const wanted = BarOrder.keys;
                for (let i = order.count - 1; i >= 0; --i)
                    if (!wanted.includes(order.get(i).key)) order.remove(i);
                for (let i = 0; i < wanted.length; ++i) {
                    if (i < order.count && order.get(i).key === wanted[i]) continue;
                    let from = -1;
                    for (let j = i + 1; j < order.count; ++j)
                        if (order.get(j).key === wanted[i]) { from = j; break; }
                    if (from >= 0) order.move(from, i, 1);
                    else order.insert(i, { key: wanted[i] });
                }
            }
            Component.onCompleted: sync()
            Connections {
                target: BarOrder
                function onKeysChanged() { if (buttons.dragKey === "") buttons.sync(); }
            }

            property string dragKey: ""
            function dragTo(y) {
                let from = -1;
                for (let i = 0; i < order.count; ++i) if (order.get(i).key === dragKey) from = i;
                const to = indexAt(width / 2, y);
                if (from >= 0 && to >= 0 && to !== from) order.move(from, to, 1);
            }
            function drop() {
                const keys = [];
                for (let i = 0; i < order.count; ++i) keys.push(order.get(i).key);
                dragKey = "";
                BarOrder.setOrder(keys);
            }

            // Обёртка: невидимая кнопка (батареи нет, раскладка одна) места
            // не занимает; у видимой снизу промежуток 6.
            delegate: Item {
                id: slot
                required property string key
                readonly property Item button: loader.item
                readonly property bool shown: button !== null && button.visible
                readonly property real topGap: key === "clock" ? 4 : 0
                width: ListView.view.width
                height: shown ? topGap + button.implicitHeight + 6 : 0
                z: buttons.dragKey === key ? 1 : 0
                scale: buttons.dragKey === key ? 1.1 : 1
                Behavior on scale { NumberAnimation { duration: Theme.animFast } }

                Loader {
                    id: loader
                    y: slot.topGap
                    anchors.horizontalCenter: parent.horizontalCenter
                    sourceComponent: ({
                        keyboard: keyboardButton, network: networkButton, battery: batteryButton,
                        brightness: brightnessButton, volume: volumeButton,
                        notifications: notificationsButton, clock: clockButton,
                    })[slot.key] ?? null
                }

                DragHandler {
                    target: null
                    xAxis.enabled: false
                    enabled: slot.shown
                    onActiveChanged: {
                        if (active) {
                            if (bar.tooltip) bar.tooltip.hide();
                            buttons.dragKey = slot.key;
                        } else if (buttons.dragKey === slot.key) {
                            buttons.drop();
                        }
                    }
                    onCentroidChanged: {
                        if (active) buttons.dragTo(slot.mapToItem(buttons.contentItem, centroid.position.x, centroid.position.y).y);
                    }
                }
            }

            displaced: Transition {
                NumberAnimation { property: "y"; duration: Theme.animNormal; easing.type: Easing.OutCubic }
            }
            move: Transition {
                NumberAnimation { property: "y"; duration: Theme.animNormal; easing.type: Easing.OutCubic }
            }
        }
    }

    Component { id: keyboardButton; KeyboardLayout { tooltip: bar.tooltip } }
    Component { id: networkButton; NetworkButton { screenName: bar.screenName; tooltip: bar.tooltip } }
    Component { id: batteryButton; Battery { screenName: bar.screenName; tooltip: bar.tooltip } }
    Component { id: brightnessButton; BrightnessButton { screenName: bar.screenName; tooltip: bar.tooltip } }
    Component { id: volumeButton; Volume { screenName: bar.screenName; tooltip: bar.tooltip } }
    Component { id: notificationsButton; NotificationsButton { screenName: bar.screenName; tooltip: bar.tooltip } }
    Component { id: clockButton; Clock { screenName: bar.screenName; tooltip: bar.tooltip } }
}
