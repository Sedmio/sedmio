import QtQuick

// Маленький рабочий стол: обои, панели по макету и окно — в цветах темы.
// Им рисуются карточки тем и карточки расположения панелей.
//   layout: "left" — полоса слева; "dock" — сверху панель, снизу док;
//           "taskbar" — сверху панель, снизу панель задач.
//   c: цвета темы {paper, surface, line, ink, inkMuted, green, terracotta,
//      windowTitle, wallpaperTop, wallpaperBottom}.
Rectangle {
    id: desk
    property string layout: "left"
    property var c: ({})

    readonly property bool side: layout === "left"
    readonly property real topH: side ? 0 : height * 0.075
    readonly property real bottomH: layout === "taskbar" ? height * 0.1 : 0
    readonly property real leftW: side ? width * 0.07 : 0

    clip: true
    gradient: Gradient {
        GradientStop { position: 0.0; color: desk.c.wallpaperTop ?? "#e4eadf" }
        GradientStop { position: 1.0; color: desk.c.wallpaperBottom ?? "#bdd0b7" }
    }

    // Значки программ: первый — знак Sedmio, остальные приглушены.
    component Icons: Repeater {
        id: icons
        property real size
        model: 3
        Rectangle {
            required property int index
            width: icons.size
            height: width
            radius: width * 0.25
            color: index === 0 ? desk.c.green : desk.c.inkMuted
            opacity: index === 0 ? 1 : 0.45
        }
    }

    Rectangle {
        id: window
        x: desk.leftW + (desk.width - desk.leftW) * 0.14
        y: desk.topH + (desk.height - desk.topH - desk.bottomH) * 0.14
        width: (desk.width - desk.leftW) * 0.72
        height: (desk.height - desk.topH - desk.bottomH) * (desk.layout === "dock" ? 0.62 : 0.72)
        radius: desk.height * 0.05
        color: desk.c.surface
        border.width: 1
        border.color: desk.c.line
        clip: true

        Rectangle {
            width: parent.width
            height: parent.height * 0.17
            color: desk.c.windowTitle
            radius: parent.radius
            Rectangle {
                anchors { right: parent.right; rightMargin: parent.height * 0.4; verticalCenter: parent.verticalCenter }
                width: parent.height * 0.35
                height: width
                radius: width / 2
                color: desk.c.terracotta
            }
        }

        Column {
            x: parent.width * 0.08
            y: parent.height * 0.3
            spacing: parent.height * 0.08
            Rectangle { width: window.width * 0.55; height: window.height * 0.07; radius: height / 2; color: desk.c.ink }
            Rectangle { width: window.width * 0.4; height: window.height * 0.05; radius: height / 2; color: desk.c.inkMuted }
            Rectangle { width: window.width * 0.3; height: window.height * 0.16; radius: height / 2; color: desk.c.green }
        }
    }

    // Полоса слева.
    Rectangle {
        visible: desk.side
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
        width: desk.leftW
        color: desk.c.paper
        Column {
            anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: desk.leftW * 0.4 }
            spacing: desk.leftW * 0.3
            Icons { size: desk.leftW * 0.5 }
        }
    }

    // Верхняя панель: часы посередине, значки справа.
    Rectangle {
        visible: !desk.side
        width: parent.width
        height: desk.topH
        color: desk.c.paper
        Rectangle {
            anchors.centerIn: parent
            width: desk.width * 0.14
            height: parent.height * 0.3
            radius: height / 2
            color: desk.c.ink
            opacity: 0.55
        }
        Row {
            anchors { right: parent.right; rightMargin: parent.height * 0.5; verticalCenter: parent.verticalCenter }
            spacing: parent.height * 0.3
            Repeater {
                model: 3
                Rectangle {
                    width: desk.topH * 0.35
                    height: width
                    radius: width / 2
                    color: desk.c.inkMuted
                }
            }
        }
    }

    // Док по центру внизу.
    Rectangle {
        visible: desk.layout === "dock"
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: desk.height * 0.035 }
        width: dockRow.width + height * 0.5
        height: desk.height * 0.11
        radius: height * 0.3
        color: desk.c.paper
        Row {
            id: dockRow
            anchors.centerIn: parent
            spacing: parent.height * 0.2
            Icons { size: desk.height * 0.07 }
        }
    }

    // Панель задач на всю ширину.
    Rectangle {
        visible: desk.layout === "taskbar"
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: desk.bottomH
        color: desk.c.paper
        Row {
            anchors { left: parent.left; leftMargin: desk.bottomH * 0.3; verticalCenter: parent.verticalCenter }
            spacing: desk.bottomH * 0.25
            Icons { size: desk.bottomH * 0.55 }
        }
    }
}
