import QtQuick
import QtQuick.Layouts
import Quickshell
import Sedmio.Style

// Панель слева, часть рамки. Сверху знак Sedmio и открытые окна,
// снизу трей, раскладка, сеть, батарея, яркость, звук, уведомления, часы
// и быстрые настройки.
Item {
    id: bar
    required property var window     // окно рамки: меню трея, сворачивание
    required property string screenName
    required property Item tooltip

    // Правый щелчок по пустому месту панели — меню, как у панели задач
    // Windows. Под кнопками: их щелчки до него не доходят.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        onClicked: event => {
            const p = mapToItem(null, event.x, event.y);
            barMenu.anchor.rect.x = p.x;
            barMenu.anchor.rect.y = p.y;
            barMenu.visible = true;
        }
    }

    ContextMenu {
        id: barMenu
        anchor.window: bar.window
        anchor.rect.width: 1
        anchor.rect.height: 1
        anchor.edges: Edges.Bottom | Edges.Right
        anchor.gravity: Edges.Bottom | Edges.Right
        items: [
            { icon: "utilities-system-monitor", text: "Диспетчер задач", action: "tasks" },
            { icon: "user-desktop", text: "Показать рабочий стол", action: "desktop" },
            { separator: true },
            { icon: "preferences-system", text: "Параметры", action: "settings" },
        ]
        onTriggered: action => {
            ShellState.closeAll(false);
            if (action === "tasks") ShellState.launch("sedmio-tasks", ["sedmio-tasks"]);
            else if (action === "settings") ShellState.launch("", ["/usr/lib/sedmio/open-settings"]);
            else if (action === "desktop") Quickshell.execDetached(["busctl", "--user", "call", "org.kde.kglobalaccel",
                "/component/kwin", "org.kde.kglobalaccel.Component", "invokeShortcut", "s", "Show Desktop"]);
        }
    }

    ColumnLayout {
        id: topGroup
        anchors { top: parent.top; left: parent.left; right: parent.right; topMargin: Theme.border + 4 }
        spacing: 8

        LauncherButton {
            Layout.alignment: Qt.AlignHCenter
            screenName: bar.screenName
            tooltip: bar.tooltip
        }

        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: 22
            implicitHeight: 2
            radius: 1
            color: Theme.line
        }
    }

    WindowList {
        anchors {
            top: topGroup.bottom; topMargin: 8
            bottom: bottomGroup.top; bottomMargin: 8
            left: parent.left; right: parent.right
        }
        window: bar.window
        tooltip: bar.tooltip
    }

    ColumnLayout {
        id: bottomGroup
        anchors { bottom: parent.bottom; left: parent.left; right: parent.right; bottomMargin: Theme.border + 6 }
        spacing: 6

        Tray {
            Layout.alignment: Qt.AlignHCenter
            window: bar.window
            tooltip: bar.tooltip
        }

        KeyboardLayout {
            Layout.alignment: Qt.AlignHCenter
            tooltip: bar.tooltip
        }

        NetworkButton {
            Layout.alignment: Qt.AlignHCenter
            screenName: bar.screenName
            tooltip: bar.tooltip
        }

        Battery {
            Layout.alignment: Qt.AlignHCenter
            screenName: bar.screenName
            tooltip: bar.tooltip
        }

        BrightnessButton {
            Layout.alignment: Qt.AlignHCenter
            screenName: bar.screenName
            tooltip: bar.tooltip
        }

        Volume {
            Layout.alignment: Qt.AlignHCenter
            screenName: bar.screenName
            tooltip: bar.tooltip
        }

        NotificationsButton {
            Layout.alignment: Qt.AlignHCenter
            screenName: bar.screenName
            tooltip: bar.tooltip
        }

        Clock {
            Layout.alignment: Qt.AlignHCenter
            screenName: bar.screenName
            Layout.topMargin: 4
            tooltip: bar.tooltip
        }

        QuickSettingsButton {
            Layout.alignment: Qt.AlignHCenter
            screenName: bar.screenName
            tooltip: bar.tooltip
        }
    }
}
