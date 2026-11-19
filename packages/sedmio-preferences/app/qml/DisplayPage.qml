import QtQuick
import Sedmio.Preferences

// «Экран»: схема экранов, у выбранного — разрешение, частота, масштаб,
// ориентация. Правки применяются кнопкой; после неё 15 секунд на «Оставить»,
// иначе прежние параметры возвращаются сами.
Page {
    id: root
    required property Displays displays
    title: "Экран"

    property int selectedId: -1
    readonly property var outputs: displays.outputs
    readonly property var enabledOutputs: outputs.filter(o => o.enabled)
    readonly property var selected: {
        for (const o of outputs)
            if (o.id === selectedId) return o;
        return outputs.length > 0 ? outputs[0] : null;
    }
    readonly property bool waiting: displays.revertIn > 0

    readonly property var scales: [1, 1.25, 1.5, 1.75, 2]
    readonly property var scaleChoices: {
        const list = scales.slice();
        if (selected && !list.some(s => Math.abs(s - selected.scale) < 0.01)) {
            list.push(selected.scale);
            list.sort((a, b) => a - b);
        }
        return list;
    }
    readonly property var rotations: ["Альбомная", "Книжная", "Альбомная (перевёрнутая)", "Книжная (перевёрнутая)"]

    function scaleLabel(s) { return Math.round(s * 100) + " %" + (Math.abs(s - 1) < 0.01 ? " (без масштаба)" : ""); }

    SText {
        visible: !root.displays.ready && root.displays.error === ""
        text: "Узнаём, какие экраны подключены…"
        color: Theme.inkMuted
    }

    // ---- Схема: включённые экраны в ряд, в масштабе
    Rectangle {
        visible: root.enabledOutputs.length > 1 || root.outputs.length > 1
        width: parent.width
        height: 200
        radius: Theme.radius
        color: Theme.paperDeep

        Item {
            id: scheme
            anchors.fill: parent
            anchors.margins: 20
            readonly property real totalWidth: {
                let w = 0;
                for (const o of root.enabledOutputs) w = Math.max(w, o.x + o.width);
                return Math.max(w, 1);
            }
            readonly property real totalHeight: {
                let h = 0;
                for (const o of root.enabledOutputs) h = Math.max(h, o.y + o.height);
                return Math.max(h, 1);
            }
            readonly property real k: Math.min(width / totalWidth, height / totalHeight)
            readonly property real offsetX: (width - totalWidth * k) / 2
            readonly property real offsetY: (height - totalHeight * k) / 2

            Repeater {
                model: root.enabledOutputs
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    readonly property bool current: root.selected && root.selected.id === modelData.id
                    x: scheme.offsetX + modelData.x * scheme.k + 2
                    y: scheme.offsetY + modelData.y * scheme.k + 2
                    width: modelData.width * scheme.k - 4
                    height: modelData.height * scheme.k - 4
                    radius: 8
                    color: current ? Theme.green : Theme.surface
                    border.width: 1
                    border.color: current ? Theme.green : Theme.lineStrong
                    Column {
                        anchors.centerIn: parent
                        width: parent.width - 12
                        SText {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            text: parent.parent.index + 1
                            size: 22
                            weight: 650
                            color: parent.parent.current ? Theme.textOnGreen : Theme.ink
                        }
                        SText {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            text: parent.parent.modelData.title + (parent.parent.modelData.primary ? " · главный" : "")
                            size: Theme.fontSmall
                            elide: Text.ElideRight
                            color: parent.parent.current ? Theme.textOnGreen : Theme.inkSoft
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.selectedId = parent.modelData.id
                    }
                }
            }
        }
    }

    // Выключенные экраны на схеме не видны — выбрать их здесь.
    Row {
        visible: root.outputs.length > root.enabledOutputs.length
        spacing: 8
        SText {
            anchors.verticalCenter: parent.verticalCenter
            text: "Выключены:"
            color: Theme.inkSoft
        }
        Repeater {
            model: root.outputs.filter(o => !o.enabled)
            delegate: SButton {
                required property var modelData
                text: modelData.title
                primary: root.selected && root.selected.id === modelData.id
                onClicked: root.selectedId = modelData.id
            }
        }
    }

    Card {
        visible: root.selected !== null
        title: root.selected ? root.selected.title + (root.selected.builtin ? "" : " · " + root.selected.connector) : ""

        Setting {
            visible: root.outputs.length > 1
            label: "Показывать изображение на этом экране"
            hint: root.selected && root.selected.enabled && root.enabledOutputs.length === 1
                ? "Единственный включённый экран выключить нельзя." : ""
            SSwitch {
                checked: root.selected ? root.selected.enabled : false
                opacity: root.selected && root.selected.enabled && root.enabledOutputs.length === 1 ? 0.45 : 1
                onToggled: root.displays.setEnabled(root.selected.id, !checked)
            }
        }
        Setting {
            visible: root.enabledOutputs.length > 1 && root.selected && root.selected.enabled
            label: "Главный экран"
            hint: "На нём панель и новые окна."
            SSwitch {
                checked: root.selected ? root.selected.primary : false
                onToggled: if (!checked) root.displays.setPrimary(root.selected.id)
            }
        }
        Setting {
            visible: root.enabledOutputs.length > 1 && root.selected && root.selected.enabled
            label: "Расположение"
            hint: "Где этот экран относительно остальных."
            Row {
                spacing: 8
                SButton { text: "← Левее"; onClicked: root.displays.move(root.selected.id, -1) }
                SButton { text: "Правее →"; onClicked: root.displays.move(root.selected.id, 1) }
            }
        }
        Setting {
            visible: root.selected && root.selected.enabled
            label: "Разрешение"
            Choice {
                model: root.selected ? root.selected.resolutions.map(r => r.label) : []
                currentIndex: root.selected ? root.selected.resolution : -1
                onActivated: index => root.displays.setResolution(root.selected.id, index)
            }
        }
        Setting {
            visible: root.selected && root.selected.enabled && root.selected.rates.length > 1
            label: "Частота обновления"
            hint: "Чем выше, тем плавнее движение."
            Choice {
                model: root.selected ? root.selected.rates.map(r => r.label) : []
                currentIndex: root.selected ? root.selected.rate : -1
                onActivated: index => root.displays.setRate(root.selected.id, index)
            }
        }
        Setting {
            visible: root.selected && root.selected.enabled
            label: "Масштаб"
            hint: "Размер текста, значков и окон."
            Choice {
                model: root.scaleChoices.map(s => root.scaleLabel(s))
                currentIndex: root.selected ? root.scaleChoices.findIndex(s => Math.abs(s - root.selected.scale) < 0.01) : -1
                onActivated: index => root.displays.setScale(root.selected.id, root.scaleChoices[index])
            }
        }
        Setting {
            visible: root.selected && root.selected.enabled
            last: true
            label: "Ориентация"
            Choice {
                model: root.rotations
                currentIndex: root.selected ? root.selected.rotation : -1
                onActivated: index => root.displays.setRotation(root.selected.id, index)
            }
        }
    }

    SText {
        visible: root.displays.error !== ""
        width: parent.width
        text: root.displays.error
        color: Theme.terracotta
        wrapMode: Text.Wrap
    }

    footer: Rectangle {
        width: root.width
        height: root.waiting || root.displays.dirty ? 64 : 0
        visible: height > 0
        color: root.waiting ? Theme.terracottaSoft : Theme.surface
        Rectangle { width: parent.width; height: 1; color: Theme.line }

        SText {
            anchors { left: parent.left; leftMargin: 32; right: buttons.left; rightMargin: 16; verticalCenter: parent.verticalCenter }
            text: root.waiting
                ? "Оставить эти параметры? Если ничего не нажать, прежние вернутся через " + root.displays.revertIn + " с."
                : "Параметры изменены, но ещё не применены."
            weight: root.waiting ? 600 : 400
            wrapMode: Text.Wrap
        }

        Row {
            id: buttons
            anchors { right: parent.right; rightMargin: 32; verticalCenter: parent.verticalCenter }
            spacing: 8
            SButton {
                text: root.waiting ? "Вернуть" : "Отменить"
                onClicked: root.waiting ? root.displays.revert() : root.displays.discard()
            }
            SButton {
                primary: true
                text: root.waiting ? "Оставить" : "Применить"
                onClicked: root.waiting ? root.displays.confirm() : root.displays.apply()
            }
        }
    }
}
