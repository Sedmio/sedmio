import QtQuick
import Quickshell
import Quickshell.Widgets

// Знак Sedmio вверху панели: открывает и закрывает запуск программ.
// То же делают Meta и Alt+F1 (usr/share/kglobalaccel/sedmio-launcher.desktop).
BarButton {
    id: root
    required property string screenName
    readonly property bool open: ShellState.launcherScreen === screenName

    active: open
    hint: open ? "" : "Программы"
    onClicked: {
        if (tooltip) tooltip.hide();
        ShellState.toggleLauncher(screenName);
    }

    IconImage {
        anchors.centerIn: parent
        implicitSize: 28
        source: Quickshell.iconPath("sedmio", "start-here")
    }
}
