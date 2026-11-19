import QtQuick
import Sedmio.Style

// «Автозапуск»: какие программы открываются сами при входе. Выключить,
// убрать, добавить из меню программ.
Page {
    id: root
    title: "Автозапуск"

    Autostart { id: autostart }

    property string query
    readonly property var matches: {
        const q = query.trim().toLowerCase();
        if (q === "") return [];
        return autostart.apps.filter(a => a.search.includes(q)).slice(0, 8);
    }
    property string confirmRemove

    // На странице, а не в строке с кнопкой: и очистка поиска, и add()
    // меняют список найденного, строка уничтожается посреди обработчика —
    // и дальше в нём не видно ни поиска, ни autostart.
    function addApp(id) {
        search.text = "";
        query = "";
        autostart.add(id);
    }

    Timer {
        running: root.confirmRemove !== ""
        interval: 6000
        onTriggered: root.confirmRemove = ""
    }

    SText {
        width: parent.width
        text: "Эти программы открываются сами, когда вы входите в систему. Изменения — со следующего входа."
        color: Theme.inkMuted
        wrapMode: Text.Wrap
    }

    SText {
        width: parent.width
        visible: autostart.message !== ""
        text: autostart.message
        color: Theme.terracotta
        wrapMode: Text.Wrap
    }

    Card {
        SText {
            width: parent.width
            visible: autostart.entries.length === 0
            padding: 16
            text: "Сами при входе ничего не запускается."
            color: Theme.inkMuted
        }
        Repeater {
            model: autostart.entryModel
            Setting {
                id: row
                required property var entry
                required property int index
                readonly property var modelData: entry
                label: modelData.name
                hint: modelData.missing ? "Программа не найдена — наверное, удалена" : (modelData.enabled ? "" : "Выключено")
                last: index === autostart.entries.length - 1
                Row {
                    spacing: 12
                    SButton {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.confirmRemove === row.modelData.file ? "Точно убрать?" : "Убрать"
                        danger: root.confirmRemove === row.modelData.file
                        onClicked: {
                            if (root.confirmRemove === row.modelData.file) {
                                root.confirmRemove = "";
                                autostart.remove(row.modelData.file);
                            } else {
                                root.confirmRemove = row.modelData.file;
                            }
                        }
                    }
                    SSwitch {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !row.modelData.missing
                        checked: row.modelData.enabled
                        onToggled: autostart.setEnabled(row.modelData.file, !checked)
                    }
                }
            }
        }
    }

    Card {
        title: "Добавить программу"
        Setting {
            label: "Найти в меню"
            last: root.matches.length === 0
            SField {
                id: search
                width: 240
                placeholderText: "Название программы"
                onTextEdited: root.query = text
                Keys.onEscapePressed: { text = ""; root.query = ""; }
            }
        }
        SText {
            width: parent.width
            visible: root.query.trim() !== "" && root.matches.length === 0
            padding: 16
            text: "Не нашлось — или программа уже в автозапуске."
            color: Theme.inkMuted
        }
        Repeater {
            model: root.matches
            Setting {
                id: app
                required property var modelData
                required property int index
                label: modelData.name
                last: index === root.matches.length - 1
                SButton {
                    text: "Добавить"
                    primary: true
                    onClicked: root.addApp(app.modelData.id)
                }
            }
        }
    }
}
