import QtQuick
import QtQuick.Layouts
import Quickshell
import Sedmio.Style

// Низ запуска программ, как в «Пуске»: «Параметры» и блокировка, сон,
// выход, перезагрузка, выключение. Опасное — по второму нажатию; просьба
// нажать ещё раз появляется на месте «Параметров», чтобы кнопки под мышью
// не сдвигались.
RowLayout {
    id: root
    // Действие выбрано — закрыть меню.
    signal done()

    property string confirm: ""
    function reset() { confirm = ""; }

    spacing: 4

    Timer {
        id: confirmTimer
        interval: 4000
        onTriggered: root.confirm = ""
    }

    readonly property var actions: [
        { id: "lock", icon: "system-lock-screen", hint: "Заблокировать", safe: true,
          command: ["loginctl", "lock-session"] },
        { id: "suspend", icon: "system-suspend", hint: "Сон", safe: true,
          command: ["systemctl", "suspend"] },
        { id: "logout", icon: "system-log-out", hint: "Выйти", ask: "Ещё раз — выйти",
          command: ["busctl", "--user", "call", "org.sedmio.SessionManager", "/Shutdown", "org.kde.Shutdown", "logout"] },
        { id: "reboot", icon: "system-reboot", hint: "Перезагрузить", ask: "Ещё раз — перезагрузить",
          command: ["busctl", "--user", "call", "org.sedmio.SessionManager", "/Shutdown", "org.kde.Shutdown", "logoutAndReboot"] },
        { id: "shutdown", icon: "system-shutdown", hint: "Выключить", ask: "Ещё раз — выключить",
          command: ["busctl", "--user", "call", "org.sedmio.SessionManager", "/Shutdown", "org.kde.Shutdown", "logoutAndShutdown"] },
    ]

    function run(action) {
        if (!action.safe && confirm !== action.id) {
            confirm = action.id;
            confirmTimer.restart();
            return;
        }
        confirm = "";
        done();
        Quickshell.execDetached(action.command);
    }

    Rectangle {
        visible: root.confirm === ""
        implicitWidth: settingsRow.implicitWidth + 20
        implicitHeight: 38
        radius: 12
        color: settingsArea.containsMouse ? Theme.paperDeep : Qt.alpha(Theme.paperDeep, 0)
        Behavior on color { ColorAnimation { duration: Theme.animFast } }
        RowLayout {
            id: settingsRow
            anchors.centerIn: parent
            spacing: 8
            SIcon { name: "configure"; symbolic: true }
            SText { text: "Параметры"; size: 13; weight: 550 }
        }
        MouseArea {
            id: settingsArea
            anchors.fill: parent
            hoverEnabled: true
            onClicked: {
                root.done();
                ShellState.launch("", ["/usr/lib/sedmio/open-settings"]);
            }
        }
    }

    Item { Layout.fillWidth: true; visible: root.confirm === "" }

    SText {
        Layout.fillWidth: true
        Layout.leftMargin: 6
        visible: root.confirm !== ""
        text: (root.actions.find(a => a.id === root.confirm) ?? {}).ask ?? ""
        color: Theme.terracotta
        size: 13
        weight: 600
        elide: Text.ElideRight
    }

    Repeater {
        model: root.actions
        Rectangle {
            id: action
            required property var modelData
            readonly property bool asking: root.confirm === modelData.id
            implicitWidth: 38
            implicitHeight: 38
            radius: 12
            color: asking ? Theme.terracotta : (actionArea.containsMouse ? Theme.paperDeep : Qt.alpha(Theme.paperDeep, 0))
            Behavior on color { ColorAnimation { duration: Theme.animFast } }
            SIcon {
                anchors.centerIn: parent
                name: action.modelData.icon
                symbolic: true
                light: action.asking
            }
            MouseArea {
                id: actionArea
                anchors.fill: parent
                hoverEnabled: true
                onClicked: root.run(action.modelData)
            }
            // Подпись над кнопкой при наведении; у крайней — не за краем.
            Rectangle {
                visible: actionArea.containsMouse && !action.asking
                anchors { bottom: parent.top; bottomMargin: 6 }
                x: Math.min((action.width - width) / 2, root.width - action.x - width)
                width: hintText.implicitWidth + 16
                height: 26
                radius: 8
                color: Theme.ink
                SText {
                    id: hintText
                    anchors.centerIn: parent
                    text: action.modelData.hint
                    size: 12
                    weight: 500
                    color: Theme.textOnGreen
                }
            }
        }
    }
}
