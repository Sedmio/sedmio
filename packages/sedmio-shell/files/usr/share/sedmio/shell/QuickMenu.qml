import QtQuick
import Quickshell
import Quickshell.Widgets
import Sedmio.Style

// Меню быстрых ссылок, как Win+X и правый клик по «Пуску» в Windows:
// параметры, диспетчер задач, терминал, «Выполнить», рабочий стол,
// завершение работы. Открывают Meta+X (usr/share/kglobalaccel/
// sedmio-quickmenu.desktop) и правый клик по знаку Sedmio на панели.
// Стрелки выбирают, Enter запускает, Esc закрывает.
Item {
    id: root
    property bool open: false
    required property string screenName
    signal closeRequested(bool restoreFocus)

    implicitWidth: 300
    implicitHeight: rows.implicitHeight + 12

    // Пункты; separator — черта между группами. Параметры — через
    // open-settings: без «Параметров» Sedmio откроется раздел KDE.
    readonly property var items: [
        { icon: "preferences-system-power-management", text: "Электропитание",
          command: ["/usr/lib/sedmio/open-settings", "power", "kcm_powerdevilprofilesconfig"] },
        { icon: "preferences-system-network", text: "Сеть",
          command: ["/usr/lib/sedmio/open-settings", "network", "kcm_networkmanagement"] },
        { icon: "help-about", text: "О системе",
          command: ["/usr/lib/sedmio/open-settings", "about", "kcm_about-distro"] },
        { icon: "preferences-system", text: "Параметры",
          command: ["/usr/lib/sedmio/open-settings"] },
        { separator: true },
        { icon: "utilities-system-monitor", text: "Диспетчер задач", id: "sedmio-tasks",
          command: ["sedmio-tasks"] },
        { icon: "system-file-manager", text: "Файлы", id: "sedmio-files",
          command: ["sedmio-files"] },
        { icon: "utilities-terminal", text: "Терминал", id: "com.mitchellh.ghostty",
          command: ["ghostty", "--gtk-single-instance=true"] },
        { separator: true },
        { icon: "system-run", text: "Выполнить", action: "run" },
        { icon: "user-desktop", text: "Рабочий стол", action: "desktop" },
        { separator: true },
        { icon: "system-shutdown", text: "Завершение работы или выход…", action: "logout" },
    ]

    property int current: 0

    onOpenChanged: {
        if (!open) return;
        current = 0;
        keys.forceActiveFocus();
    }

    // Следующий пункт (не черта) в сторону step, по кругу.
    function step(step) {
        let i = current;
        for (let n = 0; n < items.length; n++) {
            i = (i + step + items.length) % items.length;
            if (!items[i].separator) { current = i; return; }
        }
    }

    function activate(index) {
        const item = items[index];
        if (!item || item.separator) return;
        switch (item.action) {
        case "run":
            ShellState.openLauncher(screenName);
            return;
        case "desktop":
            // Свернуть всё — то же, что Meta+D у KWin. Фокус окну не
            // возвращаем: оно сейчас свернётся.
            root.closeRequested(false);
            Quickshell.execDetached(["busctl", "--user", "call", "org.kde.kglobalaccel",
                "/component/kwin", "org.kde.kglobalaccel.Component", "invokeShortcut", "s", "Show Desktop"]);
            return;
        case "logout":
            root.closeRequested(false);
            Quickshell.execDetached(["busctl", "--user", "call", "org.kde.LogoutPrompt",
                "/LogoutPrompt", "org.kde.LogoutPrompt", "promptAll"]);
            return;
        }
        root.closeRequested(false);
        ShellState.launch(item.id || "", item.command);
    }

    Rectangle {
        id: keys
        anchors.fill: parent
        radius: 12
        color: Qt.alpha(Theme.surface, Theme.glassOpacity ?? 1)
        border.width: 1
        border.color: Theme.line

        Keys.onPressed: event => {
            switch (event.key) {
            case Qt.Key_Escape:
                root.closeRequested(true);
                break;
            case Qt.Key_Return:
            case Qt.Key_Enter:
            case Qt.Key_Space:
                root.activate(root.current);
                break;
            case Qt.Key_Down:
            case Qt.Key_Tab:
                root.step(1);
                break;
            case Qt.Key_Up:
            case Qt.Key_Backtab:
                root.step(-1);
                break;
            case Qt.Key_Home:
                root.current = 0;
                break;
            case Qt.Key_End:
                root.current = root.items.length - 1;
                break;
            default:
                return;
            }
            event.accepted = true;
        }

        Column {
            id: rows
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 6 }
            spacing: 2

            Repeater {
                model: root.items

                Item {
                    id: row
                    required property var modelData
                    required property int index
                    width: rows.width
                    height: modelData.separator ? 9 : 36

                    Rectangle {
                        visible: !!row.modelData.separator
                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 8 }
                        height: 1
                        color: Theme.line
                    }

                    Rectangle {
                        visible: !row.modelData.separator
                        anchors.fill: parent
                        radius: 8
                        color: root.current === row.index ? Theme.paperDeep : Qt.alpha(Theme.paperDeep, 0)
                        Behavior on color { ColorAnimation { duration: Theme.animFast } }

                        IconImage {
                            id: rowIcon
                            anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                            implicitSize: 18
                            source: row.modelData.icon ? Icons.path(row.modelData.icon, true) : ""
                        }
                        SText {
                            anchors { left: rowIcon.right; leftMargin: 10; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                            elide: Text.ElideRight
                            size: 13
                            text: row.modelData.text || ""
                        }
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onContainsMouseChanged: if (containsMouse) root.current = row.index
                            onClicked: root.activate(row.index)
                        }
                    }
                }
            }
        }
    }
}
