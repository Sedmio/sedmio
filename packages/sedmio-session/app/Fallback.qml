import QtQuick

// Простой экран выхода — на случай, если основной (SedmioLogout.qml) не
// загрузился. Только Qt Quick: ни тем, ни шрифтов, ни значков Sedmio.
Rectangle {
    id: root
    color: "#ecefe6"

    signal logoutRequested()
    signal haltRequested()
    signal rebootRequested()
    signal cancelRequested()

    readonly property bool showAll: sdtype === ShutdownType.ShutdownTypeDefault
    readonly property bool isReboot: sdtype === ShutdownType.ShutdownTypeReboot
    readonly property bool isHalt: sdtype === ShutdownType.ShutdownTypeHalt

    focus: true
    Keys.onEscapePressed: cancelRequested()

    MouseArea { anchors.fill: parent; onClicked: root.cancelRequested() }

    Column {
        anchors.centerIn: parent
        spacing: 24

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.isHalt ? "Выключить компьютер?" : root.isReboot ? "Перезагрузить компьютер?"
                : root.showAll ? "Что сделать?" : "Завершить сеанс?"
            font.pixelSize: 28
            color: "#1d2419"
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 12
            Choice { text: "Выключить"; visible: maysd && (root.showAll || root.isHalt); onClicked: root.haltRequested() }
            Choice { text: "Перезагрузить"; visible: maysd && (root.showAll || root.isReboot); onClicked: root.rebootRequested() }
            Choice { text: "Выйти"; visible: canLogout && !root.isHalt && !root.isReboot; onClicked: root.logoutRequested() }
            Choice { text: "Отмена"; onClicked: root.cancelRequested() }
        }
    }

    component Choice: Rectangle {
        id: choice
        property alias text: label.text
        signal clicked()
        width: label.implicitWidth + 40
        height: 44
        radius: 8
        color: area.containsMouse || activeFocus ? "#ffffff" : "#f7f8f3"
        border.width: activeFocus ? 2 : 1
        border.color: activeFocus ? "#3f7a3a" : "#c9cec0"
        activeFocusOnTab: visible
        Keys.onReturnPressed: clicked()
        Keys.onEnterPressed: clicked()
        Keys.onSpacePressed: clicked()
        Text { id: label; anchors.centerIn: parent; font.pixelSize: 16; color: "#1d2419" }
        MouseArea { id: area; anchors.fill: parent; hoverEnabled: true; onClicked: choice.clicked() }
    }
}
