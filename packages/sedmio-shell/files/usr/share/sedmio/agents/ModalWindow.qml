import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Sedmio.Style

// Окно-запрос посередине экрана, с которым сейчас работают: затемнение и
// карточка со значком, заголовком и содержимым. Пока открыто, клавиатура
// у него; закрывшись, возвращает её окну, которое было активным.
// Им сделаны запросы паролей (администратора, Wi‑Fi).
PanelWindow {
    id: root
    property bool active: false
    property string iconName: "system-lock-screen"
    property string title
    property string subtitle
    property real cardWidth: 440
    default property alias content: column.data

    // Ошибка ввода: карточка вздрагивает.
    function shake() { shakeAnimation.restart(); }

    // Экран, где окно, с которым сейчас работают.
    screen: {
        const active = ToplevelManager.activeToplevel;
        const name = active && active.screens.length > 0 ? active.screens[0].name : "";
        return Quickshell.screens.find(s => s.name === name) ?? Quickshell.screens[0];
    }
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    visible: active || shown > 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // 0 — спрятано, 1 — показано
    property real shown: active ? 1 : 0
    Behavior on shown { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }

    // KWin не возвращает клавиатуру окну сам, когда оболочка её отпускает.
    property var windowBefore: null
    onActiveChanged: {
        if (active) {
            Agents.closeShellPopups();
            windowBefore = ToplevelManager.activeToplevel;
        } else {
            if (windowBefore) windowBefore.activate();
            windowBefore = null;
        }
    }

    // Затемнение; клик мимо карточки ничего не делает — чтобы случайно не отменить.
    Rectangle {
        anchors.fill: parent
        color: Theme.shadow
        opacity: 0.35 * root.shown
        MouseArea { anchors.fill: parent }
    }

    // Высота карточки на момент закрытия: содержимое к этому времени уже
    // пустеет (запрос снят), а карточка не должна прыгать, пока гаснет.
    property real cardHeight: 0

    Item {
        anchors.centerIn: parent
        width: root.cardWidth
        height: root.active ? card.implicitHeight : root.cardHeight
        onHeightChanged: if (root.active) root.cardHeight = height
        opacity: root.shown
        scale: 0.96 + 0.04 * root.shown

        transform: Translate { id: shakeShift }
        SequentialAnimation {
            id: shakeAnimation
            NumberAnimation { target: shakeShift; property: "x"; to: -10; duration: 50 }
            NumberAnimation { target: shakeShift; property: "x"; to: 10; duration: 70 }
            NumberAnimation { target: shakeShift; property: "x"; to: -6; duration: 60 }
            NumberAnimation { target: shakeShift; property: "x"; to: 0; duration: 50 }
        }

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Theme.shadow
            shadowOpacity: 0.35
            shadowBlur: 0.9
            blurMax: 32
        }

        // Карточка видна через свою картинку. Пока окно гаснет, картинка
        // больше не обновляется: запрос уже снят, и живое содержимое
        // пустело бы на глазах. Нажатия по-прежнему получает сама карточка.
        ShaderEffectSource {
            width: card.width
            height: root.cardHeight
            sourceItem: card
            sourceRect: Qt.rect(0, 0, card.width, root.cardHeight)
            live: root.active
            hideSource: true
        }

        Rectangle {
            id: card
            width: parent.width
            implicitHeight: column.implicitHeight + 48
            radius: 22
            color: Theme.paper

            ColumnLayout {
                id: column
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 24 }
                spacing: 14

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 14

                    Rectangle {
                        implicitWidth: 48
                        implicitHeight: 48
                        radius: 14
                        color: Theme.greenWash
                        SIcon {
                            anchors.centerIn: parent
                            implicitSize: 28
                            name: root.iconName
                            fallback: "system-lock-screen"
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        SText {
                            Layout.fillWidth: true
                            text: root.title
                            size: 17
                            weight: 650
                            wrapMode: Text.Wrap
                        }
                        SText {
                            Layout.fillWidth: true
                            visible: text !== ""
                            text: root.subtitle
                            color: Theme.inkMuted
                            size: 13
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }
    }
}
