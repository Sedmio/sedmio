import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland

// Рамка вокруг экрана со скруглёнными внутренними углами, слева в неё
// встроена панель, из рамки выезжает запуск программ. Одно окно на весь
// экран поверх программ: рисовать можно где угодно, а мышь окно ловит
// только на рамке (mask), остальное уходит окнам под ним. Пока открыт
// запуск — весь экран: клик мимо него закрывает.
PanelWindow {
    id: frame
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "sedmio-frame"
    WlrLayershell.keyboardFocus: launcherOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    readonly property bool launcherOpen: ShellState.launcherScreen === screen.name

    // 0 — запуск спрятан в рамке, 1 — выехал полностью.
    property real launcherProgress: launcherOpen ? 1 : 0
    Behavior on launcherProgress {
        NumberAnimation {
            duration: frame.launcherOpen ? Theme.animNormal : Theme.animFast + 40
            easing.type: frame.launcherOpen ? Easing.OutCubic : Easing.InCubic
        }
    }

    // Высота запуска по содержимому; меняется плавно.
    readonly property real launcherMaxHeight: Math.min(hole.height - 120, 620)
    property real launcherHeight: launcher.wantedHeight + 26
    Behavior on launcherHeight {
        enabled: frame.launcherProgress === 1
        NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic }
    }

    mask: Region {
        item: content
        Region { item: frame.launcherOpen ? null : hole; intersection: Intersection.Subtract }
    }

    Item {
        id: content
        anchors.fill: parent

        // Проём рамки: здесь видны окна программ.
        Item {
            id: hole
            x: Theme.barWidth
            y: Theme.border
            width: frame.width - Theme.barWidth - Theme.border
            height: frame.height - 2 * Theme.border
        }

        // Клик мимо открытого запуска закрывает его.
        MouseArea {
            anchors.fill: hole
            enabled: frame.launcherOpen
            onClicked: ShellState.closeLauncher()
        }

        // Всё, что сделано из «бумаги» рамки, — в одном слое: так у рамки
        // и выезжающих панелей общая тень и нет шва на стыке.
        Item {
            id: paper
            anchors.fill: parent
            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Theme.shadow
                shadowOpacity: 0.28
                shadowBlur: 0.7
                blurMax: 24
            }

            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer

                ShapePath {
                    fillColor: Theme.paper
                    strokeColor: "transparent"
                    fillRule: ShapePath.OddEvenFill

                    PathRectangle { x: 0; y: 0; width: frame.width; height: frame.height }
                    PathRectangle {
                        x: hole.x; y: hole.y; width: hole.width; height: hole.height
                        radius: Theme.frameRadius
                    }
                }
            }

            DrawerShape {
                id: launcherShape
                x0: Theme.barWidth
                y0: Theme.border
                drawerWidth: 480
                drawerHeight: frame.launcherHeight * frame.launcherProgress
            }
        }

        Launcher {
            id: launcher
            open: frame.launcherOpen
            x: launcherShape.x0 + 14
            y: launcherShape.y0 + 12
            width: launcherShape.drawerWidth - 28
            height: frame.launcherHeight - 26
            maxHeight: frame.launcherMaxHeight - 26
            clip: true
            opacity: Math.max(0, frame.launcherProgress * 2 - 1)
            visible: frame.launcherProgress > 0
            transform: Translate { y: (1 - frame.launcherProgress) * -24 }
            onCloseRequested: restoreFocus => ShellState.closeLauncher(restoreFocus)
        }

        Bar {
            x: 0
            y: 0
            width: Theme.barWidth
            height: frame.height
            window: frame
            screenName: frame.screen.name
            tooltip: tooltip
        }

        Tooltip { id: tooltip }
    }
}
