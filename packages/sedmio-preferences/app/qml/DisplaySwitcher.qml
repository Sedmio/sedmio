import QtQuick
import QtQuick.Window
import Sedmio.Preferences

// Выбор режима экранов (Meta+P): только первый, повторять, расширить,
// только второй. Стрелки и Tab — выбор, Enter — применить, Esc — закрыть.
// Окно показывает и прячет DisplaySwitcher (C++), он же применяет режим.
Window {
    id: win
    width: card.width + 2 * shadowPad
    height: card.height + 2 * shadowPad
    color: "transparent"
    flags: Qt.FramelessWindowHint
    title: "Режим экранов"

    readonly property int shadowPad: 18
    property int selected: 0

    onVisibleChanged: {
        if (visible) {
            selected = Math.max(0, Switcher.current);
            autoHide.restart();
            card.forceActiveFocus();
        }
    }
    Connections {
        target: Switcher
        function onAdvance() {
            if (Switcher.choices.length > 0)
                win.selected = (win.selected + 1) % Switcher.choices.length;
            autoHide.restart();
        }
    }
    // Забыли — само закроется (с сообщением — быстрее).
    Timer {
        id: autoHide
        interval: Switcher.message !== "" ? 6000 : 20000
        onTriggered: Switcher.hideOsd()
    }

    // Мягкая тень под карточкой.
    Rectangle {
        anchors.fill: card
        anchors.margins: -6
        radius: card.radius + 6
        color: Theme.shadow
        opacity: 0.10
    }

    Rectangle {
        id: card
        x: win.shadowPad
        y: win.shadowPad
        width: Switcher.message !== "" ? messageColumn.width + 48 : tiles.width + 32
        height: Switcher.message !== "" ? messageColumn.height + 40 : tiles.height + 32
        radius: 18
        color: Theme.paper
        border.width: 1
        border.color: Theme.line
        focus: true

        Keys.onEscapePressed: Switcher.hideOsd()
        Keys.onLeftPressed: move(-1)
        Keys.onRightPressed: move(1)
        Keys.onTabPressed: move(1)
        Keys.onBacktabPressed: move(-1)
        Keys.onReturnPressed: activate()
        Keys.onEnterPressed: activate()
        Keys.onSpacePressed: activate()

        function move(step) {
            const n = Switcher.choices.length;
            if (n > 0) win.selected = (win.selected + step + n) % n;
            autoHide.restart();
        }
        function activate() {
            if (Switcher.message !== "") { Switcher.hideOsd(); return; }
            Switcher.choose(Switcher.choices[win.selected].action);
        }

        Row {
            id: tiles
            visible: Switcher.message === ""
            anchors.centerIn: parent
            spacing: 8
            Repeater {
                model: Switcher.choices
                delegate: Rectangle {
                    id: tile
                    required property var modelData
                    required property int index
                    readonly property bool isSelected: win.selected === index
                    // Узкий экран — плитки уже, чтобы все четыре влезли.
                    width: Math.max(96, Math.min(148, Math.floor((Switcher.screenWidth - 2 * win.shadowPad - 32 - 24 - 24) / 4)))
                    height: 132
                    radius: 12
                    color: isSelected ? Theme.greenWash : (area.containsMouse ? Theme.surface : "transparent")
                    border.width: isSelected ? 2 : 0
                    border.color: Theme.green
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }

                    Picture {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 22
                        action: tile.modelData.action
                    }
                    SText {
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; bottomMargin: 14; margins: 8 }
                        horizontalAlignment: Text.AlignHCenter
                        text: tile.modelData.title
                        size: 13
                        weight: tile.isSelected ? 600 : 500
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                    }
                    // Сейчас так.
                    Rectangle {
                        visible: Switcher.current === tile.index
                        anchors { top: parent.top; right: parent.right; margins: 8 }
                        width: 8
                        height: 8
                        radius: 4
                        color: Theme.leaf
                    }
                    MouseArea {
                        id: area
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: { win.selected = tile.index; autoHide.restart(); }
                        onClicked: Switcher.choose(tile.modelData.action)
                    }
                }
            }
        }

        Column {
            id: messageColumn
            visible: Switcher.message !== ""
            anchors.centerIn: parent
            spacing: 14
            SText {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(implicitWidth, 360)
                horizontalAlignment: Text.AlignHCenter
                text: Switcher.message
                wrapMode: Text.Wrap
            }
            SButton {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: Switcher.message !== "" && Switcher.message.indexOf("больше двух") >= 0
                text: "Параметры экрана"
                onClicked: Switcher.openDisplaySettings()
            }
        }
    }

    // Экран со стойкой: включён (зелёный) или нет (контур).
    component Screen: Item {
        id: screen
        property bool on: true
        property string mark: ""   // "same" — на обоих одна и та же картинка
        width: 44
        height: 40
        Rectangle {
            id: panel
            width: parent.width
            height: 30
            radius: 4
            color: screen.on ? Theme.green : "transparent"
            border.width: screen.on ? 0 : 1.5
            border.color: Theme.lineStrong
            Rectangle {
                visible: screen.on && screen.mark === "same"
                anchors.centerIn: parent
                width: 18; height: 12; radius: 2
                color: Theme.textOnGreen
                opacity: 0.85
            }
        }
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 32
            width: 14; height: 3; radius: 1.5
            color: screen.on ? Theme.green : Theme.lineStrong
        }
    }

    // Два экрана схематично: какой включён (зелёный) и что на них.
    component Picture: Item {
        id: picture
        required property string action
        readonly property bool firstOn: action !== "external"
        readonly property bool secondOn: action !== "internal"
        width: 2 * 44 + 6
        height: 40

        Screen { x: 0; on: picture.firstOn; mark: picture.action === "clone" ? "same" : "" }
        Screen { x: 50; on: picture.secondOn; mark: picture.action === "clone" ? "same" : "" }
        // «Расширить»: одна картинка через оба экрана.
        Rectangle {
            visible: picture.action === "extend"
            x: 14; y: 9
            width: picture.width - 28; height: 12; radius: 2
            color: Theme.textOnGreen
            opacity: 0.85
        }
    }
}
