// Плашка аварийного режима (см. shellwatch.h): оболочка не запустилась.
// Своими силами, без модулей оболочки и тем KDE — должна показаться,
// даже когда сломано всё остальное.
import QtQuick

Window {
    id: win
    height: 44
    color: "#3a1f1f"
    flags: Qt.FramelessWindowHint

    component BannerButton: Rectangle {
        id: button
        property alias text: label.text
        signal clicked
        implicitWidth: label.implicitWidth + 28
        implicitHeight: 30
        radius: 6
        color: area.pressed ? "#40ffffff" : area.containsMouse ? "#30ffffff" : "#20ffffff"
        Text {
            id: label
            anchors.centerIn: parent
            color: "white"
            font.pixelSize: 14
        }
        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            onClicked: button.clicked()
        }
    }

    Row {
        anchors.left: parent.left
        anchors.leftMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        spacing: 14

        Text {
            id: title
            anchors.verticalCenter: parent.verticalCenter
            text: "Оболочка Sedmio не запустилась"
            color: "white"
            font.pixelSize: 14
            font.bold: true
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "Окна — Alt+Tab, программы — Alt+Пробел, диспетчер задач — Ctrl+Shift+Esc"
            color: "#c0ffffff"
            font.pixelSize: 14
            // Узкий экран — подсказка обрезается, кнопки остаются.
            width: Math.min(implicitWidth, buttons.x - 16 - title.width - 14 - 16)
            elide: Text.ElideRight
        }
    }

    Row {
        id: buttons
        anchors.right: parent.right
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8

        BannerButton {
            text: "Перезапустить"
            onClicked: shellWatch.restart()
        }
        BannerButton {
            text: "✕"
            implicitWidth: 30
            onClicked: shellWatch.dismiss()
        }
    }
}
