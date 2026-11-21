import QtQuick
import Sedmio.Style

// Кнопки состояния (раскладка, сеть, батарея, яркость, звук, уведомления,
// часы) в порядке из BarOrder — столбиком (полоса слева) или в строку
// (верхняя панель). Зажать и потянуть — кнопка встаёт на место той, над
// которой её держат; отпустили — порядок сохраняется. Невидимая кнопка
// (батареи нет, раскладка одна) места не занимает.
ListView {
    id: buttons
    required property string screenName
    required property Item tooltip
    property bool horizontal: false
    // Каких кнопок здесь нет (часы верхней панели — посередине, отдельно).
    property var exclude: []
    readonly property real spacingAfter: 6

    orientation: horizontal ? ListView.Horizontal : ListView.Vertical
    implicitWidth: horizontal ? contentWidth : Theme.barWidth
    implicitHeight: horizontal ? Theme.buttonSize : contentHeight
    interactive: false
    model: order

    ListModel { id: order }
    function wanted() { return BarOrder.keys.filter(k => !exclude.includes(k)); }
    function sync() {
        const keys = wanted();
        for (let i = order.count - 1; i >= 0; --i)
            if (!keys.includes(order.get(i).key)) order.remove(i);
        for (let i = 0; i < keys.length; ++i) {
            if (i < order.count && order.get(i).key === keys[i]) continue;
            let from = -1;
            for (let j = i + 1; j < order.count; ++j)
                if (order.get(j).key === keys[i]) { from = j; break; }
            if (from >= 0) order.move(from, i, 1);
            else order.insert(i, { key: keys[i] });
        }
    }
    Component.onCompleted: sync()
    onExcludeChanged: sync()
    Connections {
        target: BarOrder
        function onKeysChanged() { if (buttons.dragKey === "") buttons.sync(); }
    }

    property string dragKey: ""
    function dragTo(pos) {
        let from = -1;
        for (let i = 0; i < order.count; ++i) if (order.get(i).key === dragKey) from = i;
        const to = horizontal ? indexAt(pos.x, height / 2) : indexAt(width / 2, pos.y);
        if (from >= 0 && to >= 0 && to !== from) order.move(from, to, 1);
    }
    // Исключённые кнопки (часы) остаются в общем порядке на своих местах.
    function drop() {
        const shown = [];
        for (let i = 0; i < order.count; ++i) shown.push(order.get(i).key);
        dragKey = "";
        let next = 0;
        BarOrder.setOrder(BarOrder.keys.map(k => exclude.includes(k) ? k : shown[next++]));
    }

    delegate: Item {
        id: slot
        required property string key
        readonly property Item button: loader.item
        readonly property bool shown: button !== null && button.visible
        // Часы в столбике чуть отодвинуты от кнопок над ними.
        readonly property real gap: !buttons.horizontal && key === "clock" ? 4 : 0
        width: buttons.horizontal ? (shown ? button.implicitWidth + 4 : 0) : buttons.width
        height: buttons.horizontal ? buttons.height : (shown ? gap + button.implicitHeight + buttons.spacingAfter : 0)
        z: buttons.dragKey === key ? 1 : 0
        scale: buttons.dragKey === key ? 1.1 : 1
        Behavior on scale { NumberAnimation { duration: Theme.animFast } }

        Loader {
            id: loader
            x: buttons.horizontal ? 2 : (slot.width - width) / 2
            y: buttons.horizontal ? (slot.height - height) / 2 : slot.gap
            sourceComponent: ({
                keyboard: keyboardButton, network: networkButton, battery: batteryButton,
                brightness: brightnessButton, volume: volumeButton,
                notifications: notificationsButton, clock: clockButton,
            })[slot.key] ?? null
        }

        DragHandler {
            target: null
            xAxis.enabled: buttons.horizontal
            yAxis.enabled: !buttons.horizontal
            enabled: slot.shown
            onActiveChanged: {
                if (active) {
                    if (buttons.tooltip) buttons.tooltip.hide();
                    buttons.dragKey = slot.key;
                } else if (buttons.dragKey === slot.key) {
                    buttons.drop();
                }
            }
            onCentroidChanged: {
                if (active) buttons.dragTo(slot.mapToItem(buttons.contentItem, centroid.position.x, centroid.position.y));
            }
        }
    }

    displaced: Transition {
        NumberAnimation { properties: "x,y"; duration: Theme.animNormal; easing.type: Easing.OutCubic }
    }
    move: Transition {
        NumberAnimation { properties: "x,y"; duration: Theme.animNormal; easing.type: Easing.OutCubic }
    }

    Component { id: keyboardButton; KeyboardLayout { tooltip: buttons.tooltip } }
    Component { id: networkButton; NetworkButton { screenName: buttons.screenName; tooltip: buttons.tooltip } }
    Component { id: batteryButton; Battery { screenName: buttons.screenName; tooltip: buttons.tooltip } }
    Component { id: brightnessButton; BrightnessButton { screenName: buttons.screenName; tooltip: buttons.tooltip } }
    Component { id: volumeButton; Volume { screenName: buttons.screenName; tooltip: buttons.tooltip } }
    Component { id: notificationsButton; NotificationsButton { screenName: buttons.screenName; tooltip: buttons.tooltip } }
    Component { id: clockButton; Clock { screenName: buttons.screenName; tooltip: buttons.tooltip } }
}
