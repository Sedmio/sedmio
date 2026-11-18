import QtQuick

// Крупные часы и дата под ними. Дата по-русски, как и все надписи:
// у экрана входа в live-системе язык C.
Column {
    id: root
    property date now: new Date()
    spacing: 2

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.now = new Date()
    }

    SText {
        anchors.horizontalCenter: parent.horizontalCenter
        text: Qt.formatTime(root.now, "hh:mm")
        size: 104
        weight: 300
        font.letterSpacing: -2
    }
    SText {
        anchors.horizontalCenter: parent.horizontalCenter
        readonly property string raw: root.now.toLocaleDateString(Qt.locale("ru_RU"), "dddd, d MMMM")
        text: raw.charAt(0).toUpperCase() + raw.slice(1)
        size: 19
        weight: 450
        color: Theme.inkSoft
    }
}
