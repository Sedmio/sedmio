import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import Sedmio.Style

// Рамка вокруг экрана со скруглёнными внутренними углами, слева в неё
// встроена панель. Из рамки выезжают: запуск программ (сверху слева),
// буфер обмена (сверху посередине), уведомления и ход копирования файлов
// (сверху справа), панель управления (снизу слева, у часов), индикатор
// громкости и яркости (снизу посередине).
// Одно окно на весь экран поверх программ: рисовать можно где угодно,
// а мышь окно ловит только на рамке и уведомлениях (mask), остальное
// уходит окнам под ним. Пока открыт запуск, панель управления или центр
// уведомлений — весь экран: клик мимо закрывает.
PanelWindow {
    id: frame
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "sedmio-frame"
    WlrLayershell.keyboardFocus: anyOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // Экрана может не быть, пока окно пересоздаётся (перезагрузка QML,
    // экран отключили): тогда здесь ничего не открыто.
    readonly property string screenName: screen ? screen.name : ""
    function isHere(name) { return screenName !== "" && name === screenName; }

    readonly property bool launcherOpen: isHere(ShellState.launcherScreen)
    readonly property bool controlOpen: isHere(ShellState.controlScreen)
    readonly property bool historyOpen: isHere(ShellState.notificationsScreen)
    readonly property bool clipboardOpen: isHere(ShellState.clipboardScreen)
    readonly property bool quickMenuOpen: isHere(ShellState.quickMenuScreen)
    readonly property bool anyOpen: launcherOpen || controlOpen || historyOpen || clipboardOpen || quickMenuOpen

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

    // Панель управления: так же выезжает и меняет высоту по странице.
    property real controlProgress: controlOpen ? 1 : 0
    Behavior on controlProgress {
        NumberAnimation {
            duration: frame.controlOpen ? Theme.animNormal : Theme.animFast + 40
            easing.type: frame.controlOpen ? Easing.OutCubic : Easing.InCubic
        }
    }
    readonly property real controlWidth: 400
    property real controlHeight: control.wantedHeight + 28
    Behavior on controlHeight {
        enabled: frame.controlProgress === 1
        NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic }
    }

    // Буфер обмена: выезжает из верхней полосы посередине.
    property real clipboardProgress: clipboardOpen ? 1 : 0
    Behavior on clipboardProgress {
        NumberAnimation {
            duration: frame.clipboardOpen ? Theme.animNormal : Theme.animFast + 40
            easing.type: frame.clipboardOpen ? Easing.OutCubic : Easing.InCubic
        }
    }
    readonly property real clipboardWidth: Math.min(580, hole.width - 120)
    property real clipboardHeight: clipboard.wantedHeight + 28
    Behavior on clipboardHeight {
        enabled: frame.clipboardProgress === 1
        NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic }
    }

    // Уведомления и индикатор — на экране, с которым сейчас работают.
    // Пока открыт центр уведомлений (на любом экране), карточки не всплывают.
    readonly property bool isFocusedScreen: isHere(ShellState.focusedScreen())
    // Карточки операций (копирование файлов) — там же, над уведомлениями.
    readonly property bool notificationsShown: isFocusedScreen
        && (NotificationState.popups.length > 0 || JobsState.popups.length > 0)
        && ShellState.notificationsScreen === ""
    readonly property bool osdShown: OsdState.shown && isHere(OsdState.screenName)

    // Справа сверху один выдвижной ящик: в нём либо всплывающие карточки,
    // либо центр уведомлений.
    readonly property real notificationsWidth: 400
    property real notificationsHeight: historyOpen ? history.wantedHeight + 28
        : notificationsShown ? notifications.implicitHeight + 20 : 0
    Behavior on notificationsHeight { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }

    property real osdProgress: osdShown ? 1 : 0
    Behavior on osdProgress { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }
    property real osdWidth: osd.wantedWidth
    Behavior on osdWidth { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }

    mask: Region {
        item: content
        Region { item: frame.anyOpen ? null : hole; intersection: Intersection.Subtract }
        Region { item: frame.notificationsShown ? notifications : null; intersection: Intersection.Combine }
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

        // Клик мимо открытого запуска или панели закрывает их.
        MouseArea {
            anchors.fill: hole
            enabled: frame.anyOpen
            onClicked: ShellState.closeAll()
        }

        // Выехавшие панели ловят клики целиком, вместе с полями и
        // промежутками: иначе клик мимо кнопки внутри панели провалится
        // в «клик мимо панели» выше и закроет её.
        MouseArea {
            visible: frame.launcherOpen
            x: Theme.barWidth
            y: Theme.border
            width: launcherShape.drawerWidth
            height: frame.launcherHeight
        }
        MouseArea {
            visible: frame.controlOpen
            x: Theme.barWidth
            y: frame.height - Theme.border - frame.controlHeight
            width: frame.controlWidth
            height: frame.controlHeight
        }
        MouseArea {
            visible: frame.clipboardOpen
            x: hole.x + hole.width / 2 - frame.clipboardWidth / 2
            y: Theme.border
            width: frame.clipboardWidth
            height: frame.clipboardHeight
        }
        MouseArea {
            visible: frame.quickMenuOpen
            x: quickMenu.x
            y: quickMenu.y
            width: quickMenu.width
            height: quickMenu.height
        }
        MouseArea {
            visible: frame.historyOpen
            x: frame.width - Theme.border - frame.notificationsWidth
            y: Theme.border
            width: frame.notificationsWidth
            height: frame.notificationsHeight
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

            // Уведомления: та же форма, отражённая к правому краю.
            Item {
                anchors.fill: parent
                transform: Scale { xScale: -1; origin.x: frame.width / 2 }

                DrawerShape {
                    x0: Theme.border
                    y0: Theme.border
                    drawerWidth: frame.notificationsWidth
                    drawerHeight: frame.notificationsHeight
                }
            }

            // Панель управления: та же форма, отражённая к низу экрана.
            Item {
                anchors.fill: parent
                transform: Scale { yScale: -1; origin.y: frame.height / 2 }

                DrawerShape {
                    x0: Theme.barWidth
                    y0: Theme.border
                    drawerWidth: frame.controlWidth
                    drawerHeight: frame.controlHeight * frame.controlProgress
                }
            }

            // Буфер обмена: та же форма, что у индикатора, отражённая к верху.
            Item {
                anchors.fill: parent
                transform: Scale { yScale: -1; origin.y: frame.height / 2 }

                EdgeDrawerShape {
                    centerX: hole.x + hole.width / 2
                    edgeY: frame.height - Theme.border
                    drawerWidth: frame.clipboardWidth
                    drawerHeight: frame.clipboardHeight * frame.clipboardProgress
                }
            }

            EdgeDrawerShape {
                centerX: hole.x + hole.width / 2
                edgeY: frame.height - Theme.border
                drawerWidth: frame.osdWidth
                drawerHeight: 54 * frame.osdProgress
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
            onCloseRequested: restoreFocus => ShellState.closeAll(restoreFocus)
        }

        ControlPanel {
            id: control
            open: frame.controlOpen
            section: ShellState.controlSection
            x: Theme.barWidth + 14
            y: frame.height - Theme.border - frame.controlHeight + 14
            width: frame.controlWidth - 28
            height: frame.controlHeight - 28
            maxHeight: hole.height - 60
            clip: true
            opacity: Math.max(0, frame.controlProgress * 2 - 1)
            visible: frame.controlProgress > 0
            transform: Translate { y: (1 - frame.controlProgress) * 24 }
            onCloseRequested: restoreFocus => ShellState.closeAll(restoreFocus)
        }

        ClipboardPanel {
            id: clipboard
            open: frame.clipboardOpen
            x: hole.x + hole.width / 2 - frame.clipboardWidth / 2 + 14
            y: Theme.border + 14
            width: frame.clipboardWidth - 28
            height: frame.clipboardHeight - 28
            maxHeight: Math.min(640, hole.height - 120)
            clip: true
            opacity: Math.max(0, frame.clipboardProgress * 2 - 1)
            visible: frame.clipboardProgress > 0
            transform: Translate { y: (1 - frame.clipboardProgress) * -24 }
            onCloseRequested: restoreFocus => ShellState.closeAll(restoreFocus)
        }

        NotificationCenter {
            id: history
            open: frame.historyOpen
            x: frame.width - Theme.border - frame.notificationsWidth + 14
            y: Theme.border + 14
            width: frame.notificationsWidth - 28
            height: frame.notificationsHeight - 28
            maxHeight: hole.height - 60
            clip: true
            opacity: frame.historyOpen ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
            onCloseRequested: restoreFocus => ShellState.closeAll(restoreFocus)
        }

        // Карточки операций (старые сверху), под ними уведомления (новые сверху)
        Column {
            id: notifications
            x: frame.width - Theme.border - width - 10
            y: Theme.border + 10
            width: frame.notificationsWidth - 20
            spacing: 8
            opacity: frame.notificationsShown ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: Theme.animFast } }

            add: Transition {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.animNormal }
            }
            move: Transition {
                NumberAnimation { property: "y"; duration: Theme.animNormal; easing.type: Easing.OutCubic }
            }

            Repeater {
                model: ScriptModel { values: JobsState.popups }
                JobCard {
                    required property var modelData
                    job: modelData
                    width: notifications.width
                }
            }

            Repeater {
                // ScriptModel меняет список точечно: карточки не
                // пересоздаются и их таймеры не сбрасываются.
                model: ScriptModel { values: NotificationState.popups }
                NotificationCard {
                    required property var modelData
                    notification: modelData
                    width: notifications.width
                }
            }
        }

        Osd {
            id: osd
            width: frame.osdWidth
            height: 54
            x: hole.x + hole.width / 2 - width / 2
            y: frame.height - Theme.border - 54 * frame.osdProgress
            opacity: Math.max(0, frame.osdProgress * 2 - 1)
            visible: frame.osdProgress > 0
        }

        // Меню Win+X — карточкой у знака Sedmio, поверх рамки.
        QuickMenu {
            id: quickMenu
            open: frame.quickMenuOpen
            screenName: frame.screenName
            x: Theme.barWidth + 6
            y: Theme.border + 2
            width: implicitWidth
            height: implicitHeight
            opacity: frame.quickMenuOpen ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
            transform: Translate {
                x: frame.quickMenuOpen ? 0 : -8
                Behavior on x { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
            }
            onCloseRequested: restoreFocus => ShellState.closeAll(restoreFocus)
        }

        Bar {
            x: 0
            y: 0
            width: Theme.barWidth
            height: frame.height
            window: frame
            screenName: frame.screenName
            tooltip: tooltip
        }

        Tooltip { id: tooltip }
    }
}
