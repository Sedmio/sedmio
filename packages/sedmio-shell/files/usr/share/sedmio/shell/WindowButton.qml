import QtQuick
import Quickshell
import Quickshell.Widgets

// Одно окно на панели. Клик — показать, по активному — свернуть,
// средняя кнопка — закрыть.
Item {
    id: root
    required property var toplevel
    required property var window
    required property Item tooltip

    // .desktop-файлы Quickshell читает в фоне: пересчитать, когда дочитал.
    readonly property var entry: DesktopEntries.applications.values.length >= 0
        ? DesktopEntries.heuristicLookup(toplevel.appId) : null
    readonly property string iconName: entry ? entry.icon : toplevel.appId

    height: Theme.buttonSize + 4

    // Метка активного окна на краю панели
    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        x: 2
        width: 4
        height: root.toplevel.activated ? 20 : 0
        radius: 2
        color: Theme.green
        Behavior on height { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutBack } }
    }

    BarButton {
        id: button
        anchors.centerIn: parent
        active: root.toplevel.activated
        tooltip: root.tooltip
        hint: root.toplevel.title

        onClicked: event => {
            if (event.button === Qt.MiddleButton) {
                root.toplevel.close();
            } else if (root.toplevel.activated) {
                root.updateRectangle();
                root.toplevel.minimized = true;
            } else {
                root.toplevel.activate();
            }
        }

        IconImage {
            anchors.centerIn: parent
            implicitSize: 26
            source: Quickshell.iconPath(root.iconName, true) || Quickshell.iconPath("application-x-executable")
            opacity: root.toplevel.minimized ? 0.45 : 1
            Behavior on opacity { NumberAnimation { duration: Theme.animNormal } }
        }
    }

    // Куда KWin сворачивает окно (анимация «в кнопку»).
    function updateRectangle() {
        const p = button.mapToItem(null, 0, 0);
        toplevel.setRectangle(window, Qt.rect(p.x, p.y, button.width, button.height));
    }

    Component.onCompleted: updateRectangle()
    onYChanged: updateRectangle()
}
