import QtQuick
import QtQuick.Controls
import Sedmio.Preferences
import Sedmio.Style

// «Обновление»: есть ли обновления, обновить по кнопке, снимки системы —
// вернуть прежнюю версию, если после обновления что-то сломалось.
// Работа — пакет sedmio-update (updates.h).
Page {
    id: root
    title: "Обновление"

    Updates { id: updates }

    // Вторым нажатием: "restore:<id>" | "delete:<id>" | "keep".
    property string confirm
    property bool showPackages: false
    property bool showLog: false
    // Новости Arch, где нужны ручные шаги и речь о пакетах этого компьютера
    // (или пакеты не названы).
    readonly property var actionNews: updates.news.filter(n => n.manual && (n.packages.length > 0 || n.about.length === 0))
    property var openNews: ({})

    Timer {
        running: root.confirm !== ""
        interval: 6000
        onTriggered: root.confirm = ""
    }

    function plural(n, one, few, many) {
        const d = n % 10, h = n % 100;
        if (d === 1 && h !== 11) return one;
        if (d >= 2 && d <= 4 && (h < 12 || h > 14)) return few;
        return many;
    }

    // ---- Загружена из снимка / ждёт перезагрузки

    Card {
        visible: updates.bootedSnapshot !== "" && updates.restoredTitle === ""
        Setting {
            last: true
            label: "Запущена прежняя версия системы (снимок: " + updates.bootedTitle + ")"
            hint: "Её выбрали в меню при включении компьютера. Чтобы остаться на ней, нажмите «Оставить эту версию» и перезагрузитесь. Иначе в следующий раз загрузится обычная система."
            SButton {
                text: root.confirm === "keep" ? "Точно оставить?" : "Оставить эту версию"
                primary: true
                onClicked: {
                    if (updates.busy) return;
                    if (root.confirm === "keep") {
                        root.confirm = "";
                        updates.restore(updates.bootedSnapshot);
                    } else {
                        root.confirm = "keep";
                    }
                }
            }
        }
    }

    Card {
        visible: updates.restoredTitle !== ""
        Setting {
            last: true
            label: "Система возвращена к снимку (" + updates.restoredTitle + ")"
            hint: "Изменения вступят в силу после перезагрузки."
            SButton {
                text: "Перезагрузить"
                primary: true
                onClicked: updates.reboot()
            }
        }
    }

    SText {
        width: parent.width
        visible: updates.busy || updates.message !== ""
        text: updates.busy ? updates.busyText : updates.message
        color: updates.messageIsError && !updates.busy ? Theme.terracotta : Theme.inkSoft
        wrapMode: Text.Wrap
    }

    // ---- Обновления

    Card {
        title: "Обновления"

        Setting {
            last: !progressRow.visible && !packagesRow.visible && !logRow.visible
            label: updates.upgrading ? "Обновляем систему…"
                : updates.result === "done" && updates.rebootNeeded && updates.restoredTitle === "" ? "Система обновлена — перезагрузите компьютер"
                : updates.result === "failed" ? "Обновить не получилось"
                : updates.checking ? "Проверяем…"
                : updates.updates.length > 0 ? "Доступно " + updates.updates.length + " "
                    + root.plural(updates.updates.length, "обновление", "обновления", "обновлений")
                : updates.checkError !== "" ? "Не удалось проверить обновления"
                : updates.lastCheck !== "" ? "Система обновлена"
                : "Обновления ещё не проверяли"
            hint: updates.upgrading ? "Можно закрыть окно — обновление продолжится. Не выключайте компьютер."
                : updates.result === "failed" ? (updates.failText !== "" ? updates.failText + "\n" : "")
                    + (updates.changedCount > 0
                        ? "Часть пакетов обновилась. Если что-то работает не так — верните снимок «Перед обновлением системы» ниже."
                        : "Система не изменилась.")
                : updates.checkError !== "" ? updates.checkError
                : updates.lastCheck !== "" ? "Последняя проверка: " + updates.lastCheck
                : "Система проверяет сама раз в день и сообщает, если есть что поставить."
            Row {
                spacing: 12
                SButton {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !updates.upgrading
                    text: updates.checking ? "Проверяем…" : "Проверить"
                    onClicked: if (!updates.checking) updates.check()
                }
                SButton {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !updates.upgrading && !updates.checking && updates.updates.length > 0
                        && updates.bootedSnapshot === "" && updates.restoredTitle === ""
                    text: root.actionNews.length > 0 ? "Прочитал новость, обновить" : "Обновить"
                    primary: true
                    onClicked: if (!updates.busy) updates.upgrade()
                }
                SButton {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !updates.upgrading && updates.result === "done" && updates.rebootNeeded
                        && updates.restoredTitle === ""
                    text: "Перезагрузить"
                    primary: updates.updates.length === 0
                    onClicked: updates.reboot()
                }
            }
        }

        // Ход: (n/m) из журнала pacman; неизвестно — бегущая полоска.
        Item {
            id: progressRow
            visible: updates.upgrading
            width: parent.width
            height: 52
            Rectangle {
                id: track
                anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 16; rightMargin: 16 }
                height: 6
                radius: 3
                color: Theme.paperDeep
                clip: true
                Rectangle {
                    visible: updates.progress >= 0
                    width: parent.width * Math.max(0, updates.progress)
                    height: parent.height
                    radius: 3
                    color: Theme.green
                    Behavior on width { NumberAnimation { duration: 300 } }
                }
                Rectangle {
                    id: runner
                    visible: updates.progress < 0
                    width: parent.width / 4
                    height: parent.height
                    radius: 3
                    color: Theme.green
                    NumberAnimation on x {
                        running: runner.visible && root.visible
                        from: -track.width / 4
                        to: track.width
                        duration: 1400
                        loops: Animation.Infinite
                    }
                }
            }
            SText {
                anchors { left: parent.left; right: parent.right; top: track.bottom; topMargin: 8; leftMargin: 16; rightMargin: 16 }
                text: updates.status
                size: Theme.fontSmall
                color: Theme.inkMuted
                elide: Text.ElideRight
            }
            Rectangle {
                visible: packagesRow.visible || logRow.visible
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 16; rightMargin: 16 }
                height: 1
                color: Theme.line
            }
        }

        Setting {
            id: packagesRow
            visible: updates.updates.length > 0 && !updates.upgrading
            last: !root.showPackages && !logRow.visible
            label: "Что обновится"
            SButton {
                text: root.showPackages ? "Скрыть" : "Показать"
                onClicked: root.showPackages = !root.showPackages
            }
        }
        Column {
            visible: packagesRow.visible && root.showPackages
            width: parent.width
            bottomPadding: 10
            Repeater {
                model: packagesRow.visible && root.showPackages ? updates.updates : []
                Item {
                    required property var modelData
                    width: parent.width
                    height: 26
                    SText {
                        anchors { left: parent.left; leftMargin: 16; right: versions.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                        text: modelData.name
                        size: Theme.fontSmall
                        elide: Text.ElideRight
                    }
                    SText {
                        id: versions
                        anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                        text: modelData.old + "  →  " + modelData.new
                        size: Theme.fontSmall
                        color: Theme.inkMuted
                    }
                }
            }
            Rectangle {
                visible: logRow.visible
                x: 16
                width: parent.width - 32
                height: 1
                color: Theme.line
            }
        }

        Setting {
            id: logRow
            visible: updates.log !== "" && (updates.upgrading || updates.result !== "")
            last: !root.showLog
            label: "Журнал обновления"
            SButton {
                text: root.showLog ? "Скрыть" : "Показать"
                onClicked: root.showLog = !root.showLog
            }
        }
        Item {
            visible: logRow.visible && root.showLog
            width: parent.width
            height: 280
            Rectangle {
                anchors { fill: parent; leftMargin: 12; rightMargin: 12; bottomMargin: 12 }
                radius: 8
                color: Theme.paper
                border.width: 1
                border.color: Theme.line
                Flickable {
                    id: logView
                    anchors { fill: parent; margins: 10 }
                    clip: true
                    contentWidth: width
                    contentHeight: logText.height
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    // Пока идёт — к последней строке.
                    onContentHeightChanged: if (updates.upgrading) contentY = Math.max(0, contentHeight - height)
                    TextEdit {
                        id: logText
                        width: logView.width - 12
                        text: updates.log
                        readOnly: true
                        selectByMouse: true
                        wrapMode: TextEdit.WrapAnywhere
                        font.family: "JetBrains Mono"
                        font.pixelSize: 12
                        color: Theme.inkSoft
                        selectionColor: Theme.greenSelect
                    }
                }
            }
        }
    }

    // ---- Новости Arch с прошлого обновления

    Card {
        visible: updates.news.length > 0 && (updates.updates.length > 0 || updates.upgrading || updates.result !== "")
        title: "Новости Arch с прошлого обновления"
        Column {
            width: parent.width
            topPadding: 6
            bottomPadding: 6
            Repeater {
                model: updates.news
                Column {
                    id: item
                    required property var modelData
                    required property int index
                    readonly property bool needsAction: modelData.manual && (modelData.packages.length > 0 || modelData.about.length === 0)
                    readonly property bool open: root.openNews[modelData.link] === true
                    width: parent.width
                    leftPadding: 16
                    rightPadding: 16
                    topPadding: item.index > 0 ? 0 : 10
                    bottomPadding: 10
                    spacing: 4
                    Rectangle {
                        visible: item.index > 0
                        width: parent.width - 32
                        height: 1
                        color: Theme.line
                    }
                    Item {
                        visible: item.index > 0
                        width: 1
                        height: 6
                    }
                    SText {
                        width: parent.width - 32
                        wrapMode: Text.Wrap
                        text: item.modelData.title
                        weight: 600
                        color: item.needsAction ? Theme.terracotta : Theme.ink
                    }
                    SText {
                        width: parent.width - 32
                        wrapMode: Text.Wrap
                        size: Theme.fontSmall
                        color: item.needsAction ? Theme.terracotta : Theme.inkMuted
                        text: item.modelData.date
                            + (item.needsAction ? " · нужны ваши действия: прочитайте до обновления"
                               : item.modelData.manual ? " · про " + item.modelData.about.join(", ") + " — на этом компьютере его нет"
                               : item.modelData.packages.length > 0 ? " · про " + item.modelData.packages.join(", ") : "")
                    }
                    SText {
                        width: parent.width - 32
                        wrapMode: Text.Wrap
                        maximumLineCount: item.open ? 1000 : 2
                        elide: Text.ElideRight
                        size: Theme.fontSmall
                        color: Theme.inkSoft
                        text: item.modelData.text
                    }
                    Row {
                        spacing: 16
                        SText {
                            text: item.open ? "Свернуть" : "Читать дальше"
                            size: Theme.fontSmall
                            color: Theme.green
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    const next = Object.assign({}, root.openNews);
                                    next[item.modelData.link] = !item.open;
                                    root.openNews = next;
                                }
                            }
                        }
                        SText {
                            text: "На сайте Arch"
                            size: Theme.fontSmall
                            color: Theme.green
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Qt.openUrlExternally(item.modelData.link)
                            }
                        }
                    }
                }
            }
            SText {
                x: 16
                width: parent.width - 32
                topPadding: 4
                wrapMode: Text.Wrap
                size: Theme.fontSmall
                color: Theme.inkMuted
                text: "Новости — на английском, с archlinux.org."
            }
        }
    }

    // ---- Снимки

    Card {
        title: "Снимки системы"

        SText {
            width: parent.width
            padding: 16
            text: "Перед каждой установкой, обновлением и удалением программ система сохраняет снимок. "
                + "Если потом что-то сломалось, верните прежнюю версию здесь или выберите «snapshot» в меню "
                + "при включении компьютера. Файлы в домашней папке снимки не трогают. "
                + "Хранятся 5 последних автоматических снимков, сделанные вручную — пока не удалите."
            color: Theme.inkMuted
            size: Theme.fontSmall
            wrapMode: Text.Wrap
            Rectangle {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 16; rightMargin: 16 }
                height: 1
                color: Theme.line
            }
        }

        SText {
            width: parent.width
            visible: updates.snapshotsLoaded && !updates.supported
            padding: 16
            text: updates.unsupportedReason
            color: Theme.terracotta
            wrapMode: Text.Wrap
        }
        SText {
            width: parent.width
            visible: !updates.snapshotsLoaded
            padding: 16
            text: "Загружаем список…"
            color: Theme.inkMuted
        }
        SText {
            width: parent.width
            visible: updates.snapshotsLoaded && updates.supported && updates.snapshots.length === 0
            padding: 16
            text: "Снимков пока нет — первый появится перед следующей установкой программ."
            color: Theme.inkMuted
            wrapMode: Text.Wrap
            Rectangle {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 16; rightMargin: 16 }
                height: 1
                color: Theme.line
            }
        }

        Repeater {
            model: updates.snapshots
            Setting {
                id: snap
                required property var modelData
                label: modelData.title
                hint: modelData.subtitle
                    + (modelData.booted ? " · запущена сейчас" : "")
                    + (modelData.bootMenu ? " · есть в меню загрузки" : "")
                Row {
                    spacing: 12
                    SButton {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !snap.modelData.booted
                        text: root.confirm === "delete:" + snap.modelData.id ? "Точно удалить?" : "Удалить"
                        danger: root.confirm === "delete:" + snap.modelData.id
                        onClicked: {
                            if (updates.busy) return;
                            if (root.confirm === "delete:" + snap.modelData.id) {
                                root.confirm = "";
                                updates.removeSnapshot(snap.modelData.id);
                            } else {
                                root.confirm = "delete:" + snap.modelData.id;
                            }
                        }
                    }
                    SButton {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: updates.restoredTitle === "" && !updates.upgrading
                        text: root.confirm === "restore:" + snap.modelData.id ? "Точно вернуть?" : "Вернуть"
                        primary: root.confirm === "restore:" + snap.modelData.id
                        onClicked: {
                            if (updates.busy) return;
                            if (root.confirm === "restore:" + snap.modelData.id) {
                                root.confirm = "";
                                updates.restore(snap.modelData.id);
                            } else {
                                root.confirm = "restore:" + snap.modelData.id;
                            }
                        }
                    }
                }
            }
        }

        Setting {
            visible: updates.supported
            last: true
            label: "Сделать снимок сейчас"
            hint: "Например, перед тем как менять настройки системы самому."
            Row {
                spacing: 12
                SField {
                    id: note
                    anchors.verticalCenter: parent.verticalCenter
                    width: 200
                    placeholderText: "Заметка"
                    maximumLength: 120
                    onAccepted: save.clicked()
                }
                SButton {
                    id: save
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Сохранить"
                    onClicked: {
                        if (updates.busy) return;
                        updates.createSnapshot(note.text);
                        note.text = "";
                    }
                }
            }
        }
    }
}
