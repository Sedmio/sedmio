import QtQuick
import QtQuick.Controls
import Sedmio.Preferences

// «Клавиатура»: раскладки по порядку переключения, добавить и убрать,
// клавиши переключения, своя раскладка у каждого окна. Всё применяется сразу.
Page {
    id: root
    title: "Клавиатура"

    Keyboard { id: keyboard }

    readonly property var switchKeys: [
        { id: "alt_shift", label: "Alt + Shift" },
        { id: "ctrl_shift", label: "Ctrl + Shift" },
        { id: "win_space", label: "Win + Пробел" },
        { id: "caps", label: "Caps Lock" },
        { id: "", label: "Не переключать клавишами" }
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
                    if (root.adding) search.forceActiveFocus();
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
            hint: "Ещё раскладку можно сменить щелчком по значку на панели."
            Choice {
                model: root.switchKeys.map(k => k.label)
                currentIndex: root.switchKeys.findIndex(k => k.id === keyboard.switchKey)
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

    SText {
        visible: keyboard.error !== ""
        width: parent.width
        text: keyboard.error
        color: Theme.terracotta
        wrapMode: Text.Wrap
    }

    SButton {
        text: "Повтор клавиш и другое — в параметрах KDE"
        onClicked: App.openKde("kcm_keyboard")
    }
}
