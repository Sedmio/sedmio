import QtQuick
import Sedmio.Style

// Плитка программы: значок, имя, о чём она, откуда её можно взять.
// app — строка из Catalog (search, featured, category).
Rectangle {
    id: root
    required property var app
    signal clicked()

    radius: Theme.radius
    color: area.containsMouse ? Theme.paperDeep : Theme.surface
    border.width: 1
    border.color: Theme.line
    Behavior on color { ColorAnimation { duration: Theme.animFast } }

    AppIcon {
        id: icon
        anchors { left: parent.left; leftMargin: 14; top: parent.top; topMargin: 14 }
        source: root.app.icon
        size: 52
    }
    Column {
        anchors { left: icon.right; leftMargin: 14; right: parent.right; rightMargin: 14; top: parent.top; topMargin: 13 }
        spacing: 3
        SText {
            width: parent.width
            text: root.app.name
            size: 15
            weight: 600
            elide: Text.ElideRight
        }
        SText {
            width: parent.width
            text: root.app.summary
            size: 12
            color: Theme.inkSoft
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
            lineHeight: 1.1
        }
    }
    Row {
        anchors { left: icon.right; leftMargin: 14; bottom: parent.bottom; bottomMargin: 11 }
        spacing: 6
        Pill { visible: root.app.installed !== ""; text: "Установлено"; strong: true }
        Pill { visible: root.app.installed === "" && root.app.arch; text: "Arch" }
        Pill { visible: root.app.installed === "" && root.app.flathub; text: root.app.verified ? "Flathub ✓" : "Flathub" }
    }

    component Pill: Rectangle {
        property string text
        property bool strong: false
        width: label.implicitWidth + 14
        height: 20
        radius: 10
        color: strong ? Theme.greenWash : Theme.paper
        border.width: strong ? 0 : 1
        border.color: Theme.line
        SText {
            id: label
            anchors.centerIn: parent
            text: parent.text
            size: 11
            weight: 600
            color: parent.strong ? Theme.green : Theme.inkSoft
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
