import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets

// Обои под всеми окнами. Пока своя заглушка в палитре Sedmio:
// мягкий градиент и знак. Выбор картинки — позже.
PanelWindow {
    id: root
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    color: Theme.paperDeep
    WlrLayershell.layer: WlrLayer.Background
    // «desktop» — KWin по этому имени считает слой рабочим столом (как
    // обои plasmashell): обзор окон (Meta+W), «Показать рабочий стол» и
    // эффекты рисуют наши обои, а не чёрный фон.
    WlrLayershell.namespace: "desktop"

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#E8EDE3" }
            GradientStop { position: 0.55; color: "#D6E1D0" }
            GradientStop { position: 1.0; color: "#B9CCB3" }
        }
    }

    IconImage {
        readonly property int size: Math.min(root.width, root.height) * 0.36
        implicitSize: size
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: root.width * 0.08
        anchors.bottomMargin: root.height * 0.1
        source: Quickshell.iconPath("sedmio", true)
        opacity: 0.13
    }

    // Правый клик — меню рабочего стола.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        onClicked: event => desktopMenu.openAt(event.x, event.y)
    }

    DesktopMenu {
        id: desktopMenu
        window: root
    }
}
