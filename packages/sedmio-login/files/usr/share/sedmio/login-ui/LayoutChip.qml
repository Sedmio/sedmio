import QtQuick
import Sedmio.Login as Login
import Sedmio.Style

// Текущая раскладка (её держит KWin), как в Windows: ENG, РУС; клик — следующая.
Item {
    id: root
    implicitWidth: 44
    implicitHeight: 44
    visible: layouts.layoutsList.length > 1

    Login.KeyboardLayout { id: layouts }

    // Как на панели (sedmio-shell, KeyboardLayout.qml): подписи языков из
    // Windows, остальные — кодом раскладки; своя подпись из kxkbrc главнее.
    readonly property var current: layouts.layoutsList[layouts.layout]
    readonly property var windowsLabels: ({
        "us": "ENG", "gb": "ENG", "au": "ENG", "ie": "ENG",
        "ru": "РУС", "ua": "УКР", "by": "БЕЛ", "kz": "КАЗ"
    })
    readonly property string label: current?.displayName
        || windowsLabels[current?.shortName ?? ""]
        || (current?.shortName ?? "").toUpperCase()

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: area.containsMouse ? Theme.surface : Qt.rgba(1, 1, 1, 0.35)
        border.width: 1
        border.color: area.containsMouse ? Theme.lineStrong : Theme.line
        Behavior on color { ColorAnimation { duration: Theme.animFast } }

        SText {
            anchors.centerIn: parent
            text: root.label
            size: 13
            weight: 600
            color: Theme.inkSoft
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: layouts.switchToNextLayout()
    }
}
