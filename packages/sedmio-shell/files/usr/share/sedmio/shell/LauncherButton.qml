import QtQuick
import Quickshell
import Quickshell.Widgets

// Знак Sedmio вверху панели. Пока открывает KRunner; свой запуск
// программ с поиском — следующий шаг.
BarButton {
    hint: "Программы"
    onClicked: Quickshell.execDetached(["krunner"])

    IconImage {
        anchors.centerIn: parent
        implicitSize: 28
        source: Quickshell.iconPath("sedmio", "start-here")
    }
}
