import QtQuick
import QtQuick.Controls
import Sedmio.Preferences
import Sedmio.Style

// «Клавиатура»: раскладки по порядку переключения, добавить и убрать,
// клавиши переключения, своя раскладка у каждого окна; повтор клавиш и
// Num Lock — как в «Панели управления» Windows. Всё применяется сразу.
Page {
    id: root
    title: "Клавиатура"

    Keyboard { id: keyboard }

    readonly property var switchKeys: [
        { id: "alt_shift", label: "Alt + Shift" },
        { id: "ctrl_shift", label: "Ctrl + Shift" },
        { id: "caps", label: "Caps Lock" },
        { id: "", label: "Только Win + Пробел" }
    ]

    property bool adding: false
    property var choices: []
    readonly property var found: {
        const q = search.text.trim().toLowerCase();
        return q === "" ? choices : choices.filter(c => c.search.indexOf(q) >= 0);
    }

    Card {
        title: "Раскладки"
        Repeater {
            model: keyboard.layouts
            delegate: Setting {
                id: row
                required property var modelData
                required property int index
                label: modelData.name
                hint: index === 0 ? "Первая — после входа в систему" : ""
                Row {
                    spacing: 6
                    SText {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 40
                        text: row.modelData.short
                        weight: 650
                        color: Theme.inkMuted
                    }
                    SButton {
                        text: "↑"
                        opacity: row.index > 0 ? 1 : 0.35
                        onClicked: keyboard.move(row.index, -1)
                    }
                    SButton {
                        text: "↓"
                        opacity: row.index < keyboard.layouts.length - 1 ? 1 : 0.35
                        onClicked: keyboard.move(row.index, 1)
                    }
                    SButton {
                        text: "Убрать"
                        opacity: keyboard.layouts.length > 1 ? 1 : 0.35
                        onClicked: keyboard.remove(row.index)
                    }
                }
            }
        }
        Setting {
            last: !root.adding
            label: keyboard.layouts.length >= 4 ? "Больше четырёх раскладок не бывает" : ""
            SButton {
                visible: keyboard.layouts.length < 4
                text: root.adding ? "Закрыть" : "Добавить раскладку"
                primary: !root.adding
                onClicked: {
                    if (!root.adding) root.choices = keyboard.available();
                    root.adding = !root.adding;
                    if (root.adding) {
                        search.text = "";
                        search.forceActiveFocus();
                    }
                }
            }
        }
        Item {
            visible: root.adding
            width: parent.width
            height: 340
            SField {
                id: search
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16; topMargin: 12 }
                placeholderText: "Язык: украинская, немецкая, de…"
                onAccepted: if (root.found.length > 0) { keyboard.add(root.found[0].layout); root.adding = false; }
            }
            ListView {
                id: list
                anchors { left: parent.left; right: parent.right; top: search.bottom; bottom: parent.bottom; margins: 16; topMargin: 8; bottomMargin: 8 }
                clip: true
                model: root.found
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                delegate: Rectangle {
                    required property var modelData
                    width: list.width
                    height: 32
                    radius: 8
                    color: addArea.containsMouse ? Theme.paperDeep : "transparent"
                    SText {
                        anchors { left: parent.left; leftMargin: 10; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                        text: parent.modelData.name
                        elide: Text.ElideRight
                    }
                    MouseArea {
                        id: addArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: { keyboard.add(parent.modelData.layout); root.adding = false; }
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
    }

    Card {
        title: "Переключение"
        Setting {
            label: "Клавиши"
            hint: "Win + Пробел переключает всегда, как в Windows. Ещё — щелчок по значку на панели."
            Choice {
                model: root.switchKeys.map(k => k.label)
                // Параметр xkb «Win + Пробел» (выбирали раньше) — то же, что «Только Win + Пробел».
                currentIndex: root.switchKeys.findIndex(k => k.id === (keyboard.switchKey === "win_space" ? "" : keyboard.switchKey))
                onActivated: index => keyboard.setSwitchKey(root.switchKeys[index].id)
            }
        }
        Setting {
            last: true
            label: "Своя раскладка у каждого окна"
            hint: "Как в Windows: переключились в одном окне — в остальных прежняя."
            SSwitch {
                checked: keyboard.perWindow
                onToggled: keyboard.setPerWindow(!checked)
            }
        }
    }

    Card {
        title: "Повтор клавиш"
        Setting {
            label: "Задержка перед повтором"
            hint: keyboard.repeatDelay + " мс"
            // Влево — длиннее, вправо — короче, как в Windows: 1000…200 мс.
            SSlider {
                width: 260
                maximum: 1
                value: (1000 - keyboard.repeatDelay) / 800
                onMoved: value => keyboard.setRepeatDelay(Math.round((1000 - value * 800) / 10) * 10)
            }
        }
        Setting {
            label: "Скорость повтора"
            hint: Math.round(keyboard.repeatRate) + " в секунду"
            SSlider {
                width: 260
                maximum: 1
                value: (keyboard.repeatRate - 2) / 38
                onMoved: value => keyboard.setRepeatRate(Math.round(2 + value * 38))
            }
        }
        Setting {
            label: "Проверка"
            SField {
                placeholderText: "Удерживайте здесь клавишу"
            }
        }
        Setting {
            last: true
            label: "Num Lock включён после входа"
            hint: "Выключено — остаётся, как был при включении компьютера."
            SSwitch {
                checked: keyboard.numLockOn
                onToggled: keyboard.setNumLockOn(!checked)
            }
        }
    }

    SText {
        visible: keyboard.error !== ""
        width: parent.width
        text: keyboard.error
        color: Theme.terracotta
        wrapMode: Text.Wrap
    }

    SButton {
        text: "Другие параметры клавиатуры — в параметрах KDE"
        onClicked: App.openKde("kcm_keyboard")
    }
}
