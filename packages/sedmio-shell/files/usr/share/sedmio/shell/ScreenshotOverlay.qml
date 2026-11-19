import QtQuick
import Quickshell
import Quickshell.Wayland
import Sedmio.Style

// «Ножницы» на одном экране (ScreenshotState): замерший снимок экрана во
// весь экран, затемнение, выделение мышью. Отпустили кнопку — снимок готов
// (как в Windows 11). На экране, где была клавиатура, — полоска режимов:
// область, окно, весь экран, запись, закрыть. Esc — закрыть.
PanelWindow {
    id: root
    required property var modelData
    screen: modelData

    readonly property string name: modelData.name
    readonly property var shot: ScreenshotState.shots[name] ?? null
    readonly property bool hasToolbar: ScreenshotState.toolbarScreen === name
        || !ScreenshotState.shots[ScreenshotState.toolbarScreen]

    visible: ScreenshotState.active && shot !== null
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "sedmio-screenshot"
    WlrLayershell.keyboardFocus: hasToolbar ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // Выделение в точках экрана.
    property real x1: 0
    property real y1: 0
    property real x2: 0
    property real y2: 0
    property bool selecting: false
    readonly property rect selection: Qt.rect(Math.min(x1, x2), Math.min(y1, y2), Math.abs(x2 - x1), Math.abs(y2 - y1))
    readonly property bool hasSelection: selection.width >= 1 && selection.height >= 1

    onVisibleChanged: {
        selecting = false;
        x1 = x2 = y1 = y2 = 0;
        if (visible) keys.forceActiveFocus();
    }

    Image {
        anchors.fill: parent
        source: root.visible && root.shot ? "file://" + root.shot.file : ""
        cache: false
        asynchronous: true
        smooth: true
        mipmap: false
    }

    // ---- Затемнение вокруг выделения (весь экран — над тем, где курсор)

    readonly property color dim: Qt.rgba(0, 0, 0, 0.42)
    readonly property bool screenMode: ScreenshotState.mode === "screen"

    Rectangle {
        anchors.fill: parent
        visible: root.screenMode ? !area.containsMouse : !root.hasSelection
        color: root.dim
    }
    Item {
        anchors.fill: parent
        visible: !root.screenMode && root.hasSelection
        Rectangle { x: 0; y: 0; width: parent.width; height: root.selection.y; color: root.dim }
        Rectangle {
            x: 0; y: root.selection.y + root.selection.height
            width: parent.width; height: parent.height - y
            color: root.dim
        }
        Rectangle { x: 0; y: root.selection.y; width: root.selection.x; height: root.selection.height; color: root.dim }
        Rectangle {
            x: root.selection.x + root.selection.width; y: root.selection.y
            width: parent.width - x; height: root.selection.height
            color: root.dim
        }
        Rectangle {
            x: root.selection.x - 1; y: root.selection.y - 1
            width: root.selection.width + 2; height: root.selection.height + 2
            color: "transparent"
            border.width: 1
            border.color: "white"
        }
        // Размер в точках снимка.
        Rectangle {
            readonly property real sx: root.shot ? root.shot.width / root.width : 1
            x: Math.min(root.selection.x, root.width - width - 4)
            y: root.selection.y + root.selection.height + 6 + height > root.height
                ? Math.max(4, root.selection.y - height - 6) : root.selection.y + root.selection.height + 6
            width: sizeLabel.implicitWidth + 16
            height: sizeLabel.implicitHeight + 8
            radius: 6
            color: Qt.rgba(0, 0, 0, 0.6)
            SText {
                id: sizeLabel
                anchors.centerIn: parent
                text: Math.round(root.selection.width * parent.sx) + " × " + Math.round(root.selection.height * parent.sx)
                size: 12
                color: "white"
                font.features: ({ "tnum": 1 })
            }
        }
    }
    // Весь экран: рамка вокруг экрана под курсором.
    Rectangle {
        anchors.fill: parent
        visible: root.screenMode && area.containsMouse
        color: "transparent"
        border.width: 3
        border.color: Theme.green
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.screenMode ? Qt.PointingHandCursor : Qt.CrossCursor
        onPressed: mouse => {
            if (root.screenMode) return;
            root.x1 = root.x2 = mouse.x;
            root.y1 = root.y2 = mouse.y;
            root.selecting = true;
        }
        onPositionChanged: mouse => {
            if (!root.selecting) return;
            root.x2 = Math.max(0, Math.min(root.width, mouse.x));
            root.y2 = Math.max(0, Math.min(root.height, mouse.y));
        }
        onReleased: {
            if (root.screenMode) return;
            root.selecting = false;
            // Щелчок без выделения — ничего (как в Windows).
            if (root.selection.width >= 4 && root.selection.height >= 4)
                ScreenshotState.save(root.name, root.selection, root.width, root.height);
            else
                root.x1 = root.x2 = root.y1 = root.y2 = 0;
        }
        onClicked: if (root.screenMode) ScreenshotState.saveScreen(root.name)
    }

    Item {
        id: keys
        focus: true
        Keys.onEscapePressed: ScreenshotState.close()
    }

    // ---- Полоска режимов

    Rectangle {
        id: toolbar
        visible: root.hasToolbar && !root.selecting
        anchors.horizontalCenter: parent.horizontalCenter
        y: 24
        width: tools.implicitWidth + 12
        height: tools.implicitHeight + 12
        radius: 16
        color: Theme.surface
        border.width: 1
        border.color: Theme.line

        Row {
            id: tools
            anchors.centerIn: parent
            spacing: 4

            Repeater {
                model: [
                    { id: "region", icon: "select-rectangular", text: "Область" },
                    { id: "window", icon: "window", text: "Окно" },
                    { id: "screen", icon: "view-fullscreen", text: "Весь экран" }
                ]
                ToolButton {
                    required property var modelData
                    icon: modelData.icon
                    text: modelData.text
                    selected: ScreenshotState.mode === modelData.id
                    onClicked: {
                        if (modelData.id === "window") ScreenshotState.pickWindow();
                        else ScreenshotState.mode = modelData.id;
                    }
                }
            }
            Rectangle { width: 1; height: 24; anchors.verticalCenter: parent.verticalCenter; color: Theme.line }
            ToolButton {
                icon: "media-record"
                text: "Запись"
                onClicked: ScreenshotState.record()
            }
            ToolButton {
                icon: "window-close"
                text: ""
                onClicked: ScreenshotState.close()
            }
        }
    }

    Rectangle {
        visible: toolbar.visible
        anchors { horizontalCenter: parent.horizontalCenter; top: toolbar.bottom; topMargin: 8 }
        width: hint.implicitWidth + 20
        height: hint.implicitHeight + 10
        radius: height / 2
        color: Qt.rgba(0, 0, 0, 0.55)
        SText {
            id: hint
            anchors.centerIn: parent
            text: root.screenMode ? "Щёлкните по экрану, который снять"
                                  : "Выделите область — снимок сохранится сам. Esc — отмена"
            size: 12
            color: "white"
        }
    }

    component ToolButton: Rectangle {
        id: button
        property string icon
        property string text
        property bool selected: false
        signal clicked()

        implicitWidth: row.implicitWidth + (text !== "" ? 24 : 18)
        implicitHeight: 38
        radius: 11
        color: selected ? Theme.greenWash : buttonArea.containsMouse ? Theme.paperDeep : Qt.alpha(Theme.paperDeep, 0)
        Behavior on color { ColorAnimation { duration: Theme.animFast } }

        Row {
            id: row
            anchors.centerIn: parent
            spacing: 8
            SIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: button.icon
                implicitSize: 18
            }
            SText {
                anchors.verticalCenter: parent.verticalCenter
                visible: button.text !== ""
                text: button.text
                size: 13
                weight: button.selected ? 600 : 500
                color: button.selected ? Theme.green : Theme.ink
            }
        }
        MouseArea {
            id: buttonArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: button.clicked()
        }
    }
}
