import QtQuick

// Строка статуса: значок-кружок и текст.
// kind: "ok" | "warning" | "error" | "info"
Row {
    id: root

    property string kind: "info"
    property string text: ""

    readonly property color tone: kind === "ok" ? Theme.success
                                : kind === "warning" ? Theme.warning
                                : kind === "error" ? Theme.danger
                                : Theme.inkMuted

    spacing: 12

    Rectangle {
        y: Math.round((label.font.pixelSize * 1.35 - height) / 2)
        width: 18
        height: 18
        radius: 9
        color: Qt.rgba(root.tone.r, root.tone.g, root.tone.b, 0.14)

        Text {
            anchors.centerIn: parent
            text: root.kind === "ok" ? "✓" : root.kind === "info" ? "·" : "!"
            font.family: Theme.fontFamily
            font.pixelSize: 11
            font.weight: Font.Bold
            color: root.tone
        }
    }

    Text {
        id: label
        width: root.width - 30
        text: root.text
        wrapMode: Text.WordWrap
        textFormat: Text.StyledText
        lineHeight: 1.2
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontBody
        color: root.kind === "error" ? Theme.danger : Theme.ink
    }
}
