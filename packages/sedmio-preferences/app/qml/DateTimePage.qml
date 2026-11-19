import QtQuick
import QtQuick.Controls
import Sedmio.Preferences
import Sedmio.Style

// «Дата и время»: часы, автоматическое время, часовой пояс с поиском.
// Смена пояса и синхронизации спрашивает пароль (polkit).
Page {
    id: root
    title: "Дата и время"

    SystemInfo { id: system }

    property date now: new Date()
    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.now = new Date()
    }

    // Пояса тяжёлые (~400 строк) — грузим, только когда открыли выбор.
    property var zones: []
    property bool choosing: false
    readonly property var found: {
        const q = search.text.trim().toLowerCase();
        if (q === "") return zones;
        return zones.filter(z => z.search.indexOf(q) >= 0);
    }

    Column {
        spacing: 2
        SText {
            text: system.timeZone !== "" ? system.timeText(root.now) : ""
            size: 44
            weight: 600
        }
        SText {
            text: system.timeZone !== "" ? system.dateText(root.now) : ""
            color: Theme.inkSoft
        }
    }

    Card {
        Setting {
            label: "Устанавливать время автоматически"
            hint: system.canNtp ? "По серверам точного времени в интернете." : "Служба синхронизации времени не установлена."
            SSwitch {
                checked: system.ntp
                opacity: system.canNtp ? 1 : 0.45
                onToggled: if (system.canNtp) system.setNtp(!checked)
            }
        }
        Setting {
            last: !root.choosing
            label: "Часовой пояс"
            hint: system.timeZoneLabel
            SButton {
                text: root.choosing ? "Закрыть" : "Изменить"
                onClicked: {
                    if (!root.choosing && root.zones.length === 0) root.zones = system.timeZones();
                    root.choosing = !root.choosing;
                    if (root.choosing) {
                        search.text = "";
                        search.forceActiveFocus();
                    }
                }
            }
        }
        Item {
            visible: root.choosing
            width: parent.width
            height: 360
            SField {
                id: search
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16; topMargin: 12 }
                placeholderText: "Город или пояс: Москва, Asia/Tokyo, UTC+3…"
                Keys.onDownPressed: zoneList.forceActiveFocus()
                onAccepted: if (root.found.length > 0) { system.setTimeZone(root.found[0].id); root.choosing = false; }
            }
            ListView {
                id: zoneList
                anchors { left: parent.left; right: parent.right; top: search.bottom; bottom: parent.bottom; margins: 16; topMargin: 8; bottomMargin: 8 }
                clip: true
                model: root.found
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                keyNavigationEnabled: true
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    readonly property bool current: modelData.id === system.timeZone
                    width: zoneList.width
                    height: 32
                    radius: 8
                    color: current ? Theme.greenWash
                         : (zoneArea.containsMouse || (zoneList.activeFocus && zoneList.currentIndex === index)) ? Theme.paperDeep : Qt.alpha(Theme.paperDeep, 0)
                    SText {
                        anchors { left: parent.left; leftMargin: 10; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                        text: parent.modelData.label
                        elide: Text.ElideRight
                        weight: parent.current ? 600 : 400
                    }
                    MouseArea {
                        id: zoneArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: { system.setTimeZone(parent.modelData.id); root.choosing = false; }
                    }
                }
                Keys.onReturnPressed: if (currentIndex >= 0) { system.setTimeZone(root.found[currentIndex].id); root.choosing = false; }
                SText {
                    anchors.centerIn: parent
                    visible: zoneList.count === 0
                    text: "Ничего не нашлось"
                    color: Theme.inkMuted
                }
            }
        }
    }

    SText {
        visible: system.error !== ""
        width: parent.width
        text: system.error
        color: Theme.terracotta
        wrapMode: Text.Wrap
    }
}
