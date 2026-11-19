import QtQuick
import Quickshell
import Quickshell.Widgets

// Знак Sedmio вверху панели: открывает и закрывает запуск программ.
// То же делает Meta (usr/share/kglobalaccel/sedmio-launcher.desktop).
// Правый клик — меню быстрых ссылок (QuickMenu.qml), как Win+X.
BarButton {
    id: root
    required property string screenName
    readonly property bool open: ShellState.launcherScreen === screenName
        || ShellState.quickMenuScreen === screenName

    active: open
    hint: open ? "" : "Программы"
    onClicked: mouse => {
        if (tooltip) tooltip.hide();
        if (mouse.button === Qt.RightButton) ShellState.toggleQuickMenu(screenName);
        else ShellState.toggleLauncher(screenName);
    }

    IconImage {
        anchors.centerIn: parent
        implicitSize: 24
        source: Icons.path("sedmio", "start-here")
    }
}
