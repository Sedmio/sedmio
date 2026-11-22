import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import org.kde.pipewire as PipeWire
import Sedmio.Style

// Миниатюры окон программы при наведении на её кнопку, как в Windows:
// живая картинка каждого окна. KWin отдаёт её потоком PipeWire
// (WindowStream из нашей сборки Quickshell), показывает PipeWireSourceItem
// из kpipewire. Потоки идут, только пока миниатюры открыты.
// Щелчок — к окну, средняя кнопка или крестик — закрыть.
// Над кнопкой в доке и на панели задач, справа — у полосы слева.
// Загружается через Loader (WindowButton): нет kpipewire — нет только миниатюр.
//
// Своё окно слоя, а не PopupWindow: пока открыто всплывающее окно, панель
// не получает движения мыши, и соседняя кнопка не узнала бы, что на неё
// навели. Место считаем сами (place()) в координатах окна рамки — оно на
// весь экран.
PanelWindow {
    id: preview
    required property Item owner        // WindowButton
    readonly property Item button: owner.barButton
    readonly property bool horizontal: owner.horizontal
    readonly property bool hovered: hover.hovered
    signal activated()

    // Поставить у кнопки; звать перед показом.
    function place() {
        const frame = owner.window;
        const p = button.mapToItem(null, 0, 0);
        if (horizontal) {
            margins.left = Math.round(Math.max(6, Math.min(frame.width - implicitWidth - 6,
                p.x + button.width / 2 - implicitWidth / 2)));
            margins.bottom = Math.round(frame.height - p.y + 10);
        } else {
            margins.left = Math.round(p.x + button.width + 14);
            margins.top = Math.round(Math.max(6, Math.min(frame.height - implicitHeight - 6,
                p.y + button.height / 2 - implicitHeight / 2)));
        }
    }

    screen: owner.window.screen
    anchors { left: true; bottom: horizontal; top: !horizontal }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "sedmio-preview"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    color: "transparent"
    implicitWidth: cells.implicitWidth + 12
    implicitHeight: cells.implicitHeight + 12
    visible: false
    onVisibleChanged: if (visible) pop.restart()
    PopIn { id: pop; card: card }

    Rectangle {
        id: card
        anchors.fill: parent
        transformOrigin: preview.horizontal ? Item.Bottom : Item.Left
        radius: 12
        color: Theme.surface
        border.width: 1
        border.color: Theme.line

        HoverHandler { id: hover }

        Grid {
            id: cells
            x: 6
            y: 6
            columns: preview.horizontal ? Math.max(1, preview.owner.windows.length) : 1
            spacing: 4

            Repeater {
                model: preview.owner.windows

                Rectangle {
                    id: cell
                    required property var modelData
                    width: 232
                    height: 172
                    radius: 9
                    color: modelData?.activated ? Theme.greenWash
                         : cellArea.containsMouse ? Theme.paperDeep : Qt.alpha(Theme.paperDeep, 0)
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }

                    MouseArea {
                        id: cellArea
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                        onClicked: event => {
                            if (!cell.modelData) return;
                            if (event.button === Qt.MiddleButton) {
                                cell.modelData.close();
                                return;
                            }
                            cell.modelData.activate();
                            preview.activated();
                        }
                    }

                    IconImage {
                        id: cellIcon
                        x: 10
                        y: 10
                        implicitSize: 16
                        source: preview.owner.iconSource
                    }
                    SText {
                        anchors {
                            left: cellIcon.right; leftMargin: 8
                            right: closeButton.left; rightMargin: 4
                            verticalCenter: cellIcon.verticalCenter
                        }
                        elide: Text.ElideRight
                        size: 12
                        weight: cell.modelData?.activated ? 600 : 450
                        color: Theme.ink
                        text: cell.modelData?.title ?? ""
                    }
                    Rectangle {
                        id: closeButton
                        anchors { right: parent.right; rightMargin: 5; verticalCenter: cellIcon.verticalCenter }
                        width: 24
                        height: 24
                        radius: 7
                        opacity: cellArea.containsMouse || closeArea.containsMouse ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
                        color: closeArea.containsMouse ? Theme.terracottaSoft : Qt.alpha(Theme.terracottaSoft, 0)
                        SText {
                            anchors.centerIn: parent
                            size: 11
                            color: closeArea.containsMouse ? Theme.terracotta : Theme.inkMuted
                            text: "✕"
                        }
                        MouseArea {
                            id: closeArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: cell.modelData?.close()
                        }
                    }

                    // Картинка окна; пока поток не пошёл (или KWin его не
                    // дал) — значок программы.
                    Item {
                        anchors { left: parent.left; right: parent.right; top: cellIcon.bottom; bottom: parent.bottom; margins: 8 }

                        IconImage {
                            anchors.centerIn: parent
                            implicitSize: 48
                            source: preview.owner.iconSource
                            opacity: thumb.ready ? 0 : 0.5
                        }
                        PipeWire.PipeWireSourceItem {
                            id: thumb
                            anchors.fill: parent
                            nodeId: stream.nodeId
                            // Не visible: невидимый PipeWireSourceItem держит
                            // поток на паузе, и первая картинка не придёт.
                            opacity: ready ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
                        }
                        WindowStream {
                            id: stream
                            toplevel: cell.modelData
                            active: preview.visible
                        }
                    }
                }
            }
        }
    }
}
