import QtQuick
import QtQuick.Controls
import Sedmio.Tasks
import Sedmio.Style

// «Диспетчер задач» (Ctrl+Shift+Esc): программы — сколько берут и
// «Завершить»; ниже — части системы. Данные — Tasks (группы systemd).
// «Запустить новую задачу» — Launcher: открыть программу без оболочки.
ApplicationWindow {
    id: win
    width: 760
    height: 600
    minimumWidth: 560
    minimumHeight: 400
    visible: true
    color: Theme.paper
    title: "Диспетчер задач"

    Tasks {
        id: tasks
        running: win.visible && win.visibility !== Window.Minimized
    }

    // Что спросили «Завершить?» — ждём второго нажатия.
    property string confirmEnd
    // Оболочку перезапускают — поднимается несколько секунд.
    property bool restartingShell: false
    Timer {
        running: win.restartingShell
        interval: 5000
        onTriggered: win.restartingShell = false
    }

    Launcher { id: launcher }
    // Панель «Запустить новую задачу» открыта.
    property bool runOpen: false
    property var runMatches: []

    function openRun() {
        runOpen = true;
        runField.text = "";
        runField.forceActiveFocus();
        flick.contentY = 0;
    }
    function closeRun() {
        runOpen = false;
        runField.text = "";
    }
    // Enter: выбранная программа из списка, иначе строка как команда.
    function runSelected() {
        const ok = runList.currentIndex >= 0 && runList.currentIndex < win.runMatches.length
            ? launcher.launchApp(win.runMatches[runList.currentIndex].id)
            : launcher.runCommand(runField.text);
        if (ok)
            closeRun();
    }

    Shortcut { sequences: [StandardKey.Close, StandardKey.Quit]; onActivated: win.close() }
    Shortcut { sequence: "Escape"; onActivated: win.runOpen ? win.closeRun() : win.close() }

    function percent(value) {
        return value < 0.5 ? "0 %" : value < 10 ? value.toFixed(1).replace(".", ",") + " %" : Math.round(value) + " %";
    }

    Timer {
        running: win.confirmEnd !== ""
        interval: 5000
        onTriggered: win.confirmEnd = ""
    }

    // Шапка: не прокручивается; заголовка у окна нет — за неё окно и
    // таскают, справа — кнопки окна.
    Item {
        id: header
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 22 + Math.max(heading.height, runButton.height)

        WindowDragArea { anchors.fill: parent }

        SText {
            id: heading
            x: 28
            anchors.verticalCenter: runButton.verticalCenter
            text: "Диспетчер задач"
            size: 24
            weight: 650
        }
        SButton {
            id: runButton
            anchors { right: windowControls.visible ? windowControls.left : parent.right; rightMargin: windowControls.visible ? 14 : 28 }
            y: 22
            visible: !win.runOpen
            text: "Запустить новую задачу"
            onClicked: win.openRun()
        }
        WindowControls {
            id: windowControls
            anchors { right: parent.right; rightMargin: 12; verticalCenter: runButton.verticalCenter }
        }
    }

    Flickable {
        id: flick
        anchors { left: parent.left; right: parent.right; top: header.bottom; bottom: parent.bottom }
        contentHeight: column.height + 36
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
            id: column
            x: 28
            y: 18
            width: flick.width - 56
            spacing: 18

            Card {
                title: "Запустить новую задачу"
                visible: win.runOpen
                Item {
                    width: parent.width
                    height: 34 + 28
                    SField {
                        id: runField
                        anchors { left: parent.left; right: runGo.left; margins: 14; rightMargin: 8; verticalCenter: parent.verticalCenter }
                        placeholderText: "Название программы, команда или путь к файлу"
                        onTextChanged: {
                            launcher.clearError();
                            win.runMatches = launcher.search(text);
                            runList.currentIndex = win.runMatches.length > 0 ? 0 : -1;
                        }
                        Keys.onReturnPressed: win.runSelected()
                        Keys.onEnterPressed: win.runSelected()
                        Keys.onDownPressed: runList.currentIndex = Math.min(runList.currentIndex + 1, win.runMatches.length - 1)
                        Keys.onUpPressed: runList.currentIndex = Math.max(runList.currentIndex - 1, -1)
                    }
                    SButton {
                        id: runGo
                        anchors { right: runCancel.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                        primary: true
                        text: "Запустить"
                        onClicked: win.runSelected()
                    }
                    SButton {
                        id: runCancel
                        anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                        text: "Отмена"
                        onClicked: win.closeRun()
                    }
                }
                SText {
                    visible: launcher.error !== ""
                    width: parent.width
                    leftPadding: 16
                    rightPadding: 16
                    bottomPadding: 12
                    text: launcher.error
                    color: Theme.terracotta
                    wrapMode: Text.Wrap
                }
                ListView {
                    id: runList
                    width: parent.width
                    height: contentHeight
                    interactive: false
                    model: win.runMatches
                    currentIndex: -1
                    delegate: Rectangle {
                        id: match
                        required property var modelData
                        required property int index
                        width: runList.width
                        height: 48
                        color: runList.currentIndex === index ? Theme.paper : Qt.alpha(Theme.paper, 0)
                        Rectangle {
                            anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 16; rightMargin: 16 }
                            height: 1
                            color: Theme.line
                        }
                        SIcon {
                            id: matchIcon
                            anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
                            size: 24
                            name: match.modelData.icon
                        }
                        Column {
                            anchors { left: matchIcon.right; leftMargin: 12; right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                            SText {
                                width: parent.width
                                text: match.modelData.name
                                elide: Text.ElideRight
                            }
                            SText {
                                width: parent.width
                                visible: text !== ""
                                text: match.modelData.comment
                                size: Theme.fontSmall
                                color: Theme.inkMuted
                                elide: Text.ElideRight
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: runList.currentIndex = match.index
                            onClicked: {
                                runList.currentIndex = match.index;
                                win.runSelected();
                            }
                        }
                    }
                }
            }

            // Процессор и память всего.
            Row {
                width: parent.width
                spacing: 12
                Meter {
                    width: (parent.width - 12) / 2
                    label: "Процессор"
                    value: win.percent(tasks.cpu)
                    fraction: tasks.cpu / 100
                }
                Meter {
                    width: (parent.width - 12) / 2
                    label: "Память"
                    value: tasks.memoryText
                    fraction: tasks.memoryTotal > 0 ? tasks.memoryUsed / tasks.memoryTotal : 0
                }
            }

            SText {
                width: parent.width
                visible: tasks.message !== ""
                text: tasks.message
                color: Theme.terracotta
                wrapMode: Text.Wrap
            }

            SText {
                width: parent.width
                visible: !tasks.available
                text: "Не удалось прочитать группы systemd — список программ недоступен."
                color: Theme.inkMuted
                wrapMode: Text.Wrap
            }

            Card {
                title: "Программы"
                visible: tasks.available
                HeaderRow {}
                Repeater {
                    model: tasks.appModel
                    TaskRow {
                        required property var entry
                        required property int index
                        readonly property var modelData: entry
                        item: entry
                        last: index === tasks.appModel.count - 1
                        detail: modelData.hung ? "Не отвечает"
                              : modelData.ending ? "Завершается…"
                              : modelData.processes > 1 ? modelData.processes + " " + win.processWord(modelData.processes) : ""
                        detailIsError: modelData.hung
                        SButton {
                            visible: !modelData.ending
                            text: win.confirmEnd === modelData.key ? "Точно завершить?" : "Завершить"
                            danger: win.confirmEnd === modelData.key
                            onClicked: {
                                if (win.confirmEnd === modelData.key) {
                                    win.confirmEnd = "";
                                    tasks.end(modelData.key);
                                } else {
                                    win.confirmEnd = modelData.key;
                                }
                            }
                        }
                        SButton {
                            visible: modelData.hung
                            text: "Закрыть принудительно"
                            danger: true
                            onClicked: tasks.forceEnd(modelData.key)
                        }
                    }
                }
                SText {
                    visible: tasks.appModel.count === 0
                    width: parent.width
                    padding: 16
                    text: "Открытых программ нет."
                    color: Theme.inkMuted
                }
            }

            Card {
                title: "Система"
                visible: tasks.available
                Repeater {
                    model: tasks.systemModel
                    TaskRow {
                        required property var entry
                        required property int index
                        readonly property var modelData: entry
                        item: entry
                        last: index === tasks.systemModel.count - 1
                        detail: modelData.stopped ? "Не запущена — панели и меню нет" : ""
                        detailIsError: modelData.stopped
                        SButton {
                            visible: modelData.restartable
                            primary: modelData.stopped
                            text: win.restartingShell ? (modelData.stopped ? "Запуск…" : "Перезапуск…")
                                                      : (modelData.stopped ? "Запустить" : "Перезапустить")
                            enabled: !win.restartingShell
                            opacity: enabled ? 1 : 0.5
                            onClicked: {
                                win.restartingShell = true;
                                tasks.restartShell();
                            }
                        }
                    }
                }
            }

            SText {
                width: parent.width
                visible: tasks.available
                text: "«Завершить» закрывает программу целиком, со всеми её окнами; несохранённое в ней пропадёт. Перезапуск оболочки открытые программы не трогает."
                size: Theme.fontSmall
                color: Theme.inkMuted
                wrapMode: Text.Wrap
            }
        }
    }

    function processWord(n) {
        const tens = n % 100;
        const ones = n % 10;
        if (tens >= 11 && tens <= 14) return "процессов";
        if (ones === 1) return "процесс";
        if (ones >= 2 && ones <= 4) return "процесса";
        return "процессов";
    }

    // Подписи столбцов; щелчок — сортировать по нему.
    component HeaderRow: Item {
        width: parent ? parent.width : 0
        height: 34
        SortLabel { anchors { left: parent.left; leftMargin: 52; verticalCenter: parent.verticalCenter } text: "Название"; key: "name" }
        SortLabel { x: parent.width - 330 - width; anchors.verticalCenter: parent.verticalCenter; text: "Процессор"; key: "cpu" }
        SortLabel { x: parent.width - 230 - width; anchors.verticalCenter: parent.verticalCenter; text: "Память"; key: "memory" }
        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 16; rightMargin: 16 }
            height: 1
            color: Theme.line
        }
    }

    component SortLabel: SText {
        property string key
        size: Theme.fontSmall
        weight: tasks.sortBy === key ? 650 : 500
        color: tasks.sortBy === key ? Theme.ink : Theme.inkMuted
        MouseArea {
            anchors.fill: parent
            anchors.margins: -6
            cursorShape: Qt.PointingHandCursor
            onClicked: tasks.sortBy = parent.key
        }
    }

    // Строка: значок, название, процессор, память, кнопки.
    component TaskRow: Item {
        id: row
        property var item
        property bool last: false
        property string detail
        property bool detailIsError: false
        default property alias buttons: buttonRow.data

        width: parent ? parent.width : 0
        implicitHeight: Math.max(texts.height, buttonRow.height, 36) + 18

        SIcon {
            id: icon
            anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
            size: 24
            name: row.item ? row.item.icon : ""
        }
        Column {
            id: texts
            anchors { left: icon.right; leftMargin: 12; right: cpuText.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
            spacing: 2
            SText {
                width: parent.width
                text: row.item ? row.item.name : ""
                elide: Text.ElideRight
            }
            SText {
                width: parent.width
                visible: text !== ""
                text: row.detail
                size: Theme.fontSmall
                color: row.detailIsError ? Theme.terracotta : Theme.inkMuted
            }
        }
        SText {
            id: cpuText
            anchors { right: parent.right; rightMargin: 330; verticalCenter: parent.verticalCenter }
            text: row.item && !row.item.stopped ? win.percent(row.item.cpu) : ""
            color: row.item && row.item.cpu >= 50 ? Theme.terracotta : Theme.ink
        }
        SText {
            anchors { right: parent.right; rightMargin: 230; verticalCenter: parent.verticalCenter }
            text: row.item ? row.item.memoryText : ""
        }
        Row {
            id: buttonRow
            anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
            spacing: 8
        }
        Rectangle {
            visible: !row.last
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 16; rightMargin: 16 }
            height: 1
            color: Theme.line
        }
    }

    // Плашка «Процессор 12 %» с полоской.
    component Meter: Rectangle {
        property string label
        property string value
        property real fraction: 0
        height: 74
        radius: Theme.radius
        color: Theme.surface
        border.width: 1
        border.color: Theme.line
        SText {
            x: 16
            y: 12
            text: parent.label
            size: Theme.fontSmall
            color: Theme.inkMuted
        }
        SText {
            x: 16
            y: 30
            text: parent.value
            size: 18
            weight: 600
        }
        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 14 }
            height: 4
            radius: 2
            color: Theme.paperDeep
            Rectangle {
                width: parent.width * Math.max(0, Math.min(1, parent.parent.fraction))
                height: parent.height
                radius: 2
                color: parent.parent.fraction > 0.85 ? Theme.terracotta : Theme.green
                Behavior on width { NumberAnimation { duration: Theme.animNormal } }
            }
        }
    }
}
