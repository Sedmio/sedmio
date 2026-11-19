import QtQuick
import QtQuick.Effects
import "file:///usr/share/sedmio/login-ui"
import Sedmio.Style

// Экран выхода Sedmio. Его загружает sedmio-session-manager
// (LogoutWindow.qml), а в запасном окне выхода Plasma — Logout.qml пакета
// org.sedmio.shell. Свойства контекста — те же, что у
// ksmserver-logout-greeter: sdtype (что просили), ShutdownType,
// maysd (можно выключать), canLogout, spdMethods (сон, гибернация),
// softwareUpdatePending (есть обновление, ставится при перезагрузке).
//
// Как в Plasma: просили конкретное (выключить, перезагрузить) — через
// 30 секунд это и случится; просто «завершить» — выбор без отсчёта.
// Esc или клик мимо — отмена. С клавиатуры, как в Windows: Tab и стрелки
// ходят по кнопкам, Enter и Пробел нажимают выбранную.
Item {
    id: root

    signal logoutRequested()
    signal haltRequested()
    signal haltUpdateRequested()
    signal suspendRequested(int spdMethod)
    signal rebootRequested()
    signal rebootRequested2(int opt)
    signal rebootUpdateRequested()
    signal cancelRequested()
    signal lockScreenRequested()
    signal cancelSoftwareUpdateRequested()

    readonly property bool showAll: sdtype === ShutdownType.ShutdownTypeDefault
    readonly property bool isReboot: sdtype === ShutdownType.ShutdownTypeReboot
    readonly property bool isHalt: sdtype === ShutdownType.ShutdownTypeHalt
    readonly property bool updates: typeof softwareUpdatePending !== "undefined" && softwareUpdatePending

    function reboot() { if (updates) rebootUpdateRequested(); else rebootRequested(); }
    function halt() { if (updates) haltUpdateRequested(); else haltRequested(); }
    function defaultAction() {
        if (isReboot) reboot();
        else if (isHalt) halt();
        else logoutRequested();
    }

    property int remaining: 30
    Timer {
        running: !root.showAll && root.remaining > 0
        repeat: true
        interval: 1000
        onTriggered: if (--root.remaining <= 0) root.defaultAction()
    }

    Loader {
        id: taskManager
        source: "TaskManagerLauncher.qml"
    }
    Connections {
        target: taskManager.item
        function onStarted() { root.cancelRequested(); }
    }

    focus: true
    Keys.onEscapePressed: cancelRequested()
    Keys.onReturnPressed: if (!showAll) defaultAction()
    Keys.onEnterPressed: if (!showAll) defaultAction()
    // Ещё ничего не выбрано — стрелка выбирает первую кнопку.
    Keys.onLeftPressed: nextItemInFocusChain(true).forceActiveFocus(Qt.TabFocusReason)
    Keys.onRightPressed: nextItemInFocusChain(true).forceActiveFocus(Qt.TabFocusReason)

    // Бумажная завеса поверх рабочего стола.
    Rectangle {
        anchors.fill: parent
        color: Theme.paper
        opacity: 0
        Component.onCompleted: opacity = 0.97
        Behavior on opacity { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }
    }
    MouseArea {
        anchors.fill: parent
        onClicked: root.cancelRequested()
    }

    Column {
        id: content
        anchors.centerIn: parent
        spacing: 0
        opacity: 0
        scale: 0.96
        Component.onCompleted: { opacity = 1; scale = 1; }
        Behavior on opacity { NumberAnimation { duration: Theme.animNormal } }
        Behavior on scale { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }

        SText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.isHalt ? "Выключить компьютер?"
                : root.isReboot ? "Перезагрузить компьютер?"
                : root.showAll ? "Что сделать?" : "Завершить сеанс?"
            size: 30
            weight: 600
        }

        Item { width: 1; height: 10 }

        SText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.showAll ? (root.updates ? "Обновления поставятся при перезагрузке или выключении" : "Несохранённое в программах может пропасть")
                : (root.isHalt ? "Выключится" : root.isReboot ? "Перезагрузится" : "Сеанс завершится")
                  + " сам через " + root.remaining + " с"
            size: 15
            color: Theme.inkSoft
        }

        Item { width: 1; height: 40 }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 28

            Option {
                visible: root.showAll
                icon: "system-lock-screen"
                label: "Заблокировать"
                onClicked: root.lockScreenRequested()
            }
            Option {
                visible: root.showAll && spdMethods.SuspendState
                icon: "system-suspend"
                label: "Сон"
                onClicked: root.suspendRequested(2)
            }
            Option {
                visible: maysd && (root.isReboot || root.showAll)
                icon: "system-reboot"
                label: "Перезагрузить"
                primary: root.isReboot
                onClicked: root.reboot()
            }
            Option {
                visible: maysd && (root.isHalt || root.showAll)
                icon: "system-shutdown"
                label: "Выключить"
                primary: root.isHalt
                onClicked: root.halt()
            }
            Option {
                visible: canLogout && !root.isReboot && !root.isHalt
                icon: "system-log-out"
                label: "Выйти"
                primary: !root.showAll
                onClicked: root.logoutRequested()
            }
            Option {
                visible: root.showAll && taskManager.status === Loader.Ready && taskManager.item.available
                icon: "office-chart-line"
                label: "Диспетчер задач"
                onClicked: taskManager.item.run()
            }
        }

        Item { width: 1; height: 36 }

        Rectangle {
            id: cancelButton
            anchors.horizontalCenter: parent.horizontalCenter
            width: cancelText.implicitWidth + 36
            height: 38
            radius: 19
            color: cancelArea.containsMouse ? Theme.surface : "transparent"
            border.width: activeFocus ? 2 : 1
            border.color: activeFocus ? Theme.green : cancelArea.containsMouse ? Theme.lineStrong : Theme.line
            Behavior on color { ColorAnimation { duration: Theme.animFast } }

            activeFocusOnTab: true
            Keys.onReturnPressed: root.cancelRequested()
            Keys.onEnterPressed: root.cancelRequested()
            Keys.onSpacePressed: root.cancelRequested()
            Keys.onUpPressed: nextItemInFocusChain(false).forceActiveFocus(Qt.BacktabFocusReason)

            SText {
                id: cancelText
                anchors.centerIn: parent
                text: "Отмена"
                size: 14
                weight: 550
                color: Theme.inkSoft
            }
            MouseArea {
                id: cancelArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.cancelRequested()
            }
        }
    }

    // Крупная круглая кнопка с подписью. primary — то, что случится по
    // отсчёту (и по Enter).
    component Option: Item {
        id: option
        property string icon
        property string label
        property bool primary: false
        signal clicked()

        width: 96
        height: circle.height + 12 + caption.implicitHeight

        activeFocusOnTab: visible
        Keys.onReturnPressed: clicked()
        Keys.onEnterPressed: clicked()
        Keys.onSpacePressed: clicked()
        Keys.onLeftPressed: nextItemInFocusChain(false).forceActiveFocus(Qt.BacktabFocusReason)
        Keys.onRightPressed: nextItemInFocusChain(true).forceActiveFocus(Qt.TabFocusReason)
        Keys.onDownPressed: cancelButton.forceActiveFocus(Qt.TabFocusReason)

        // Выбрана с клавиатуры — кольцо вокруг кнопки.
        Rectangle {
            anchors.fill: circle
            anchors.margins: -5
            radius: width / 2
            color: "transparent"
            border.width: 2
            border.color: Theme.green
            visible: option.activeFocus
        }

        Rectangle {
            id: circle
            anchors.horizontalCenter: parent.horizontalCenter
            width: 68
            height: 68
            radius: 34
            color: option.primary ? (area.containsMouse ? Qt.lighter(Theme.green, 1.12) : Theme.green)
                 : area.containsMouse ? Theme.surface : Qt.rgba(1, 1, 1, 0.5)
            border.width: option.primary ? 0 : 1
            border.color: area.containsMouse ? Theme.lineStrong : Theme.line
            scale: area.pressed ? 0.95 : 1
            Behavior on color { ColorAnimation { duration: Theme.animFast } }
            Behavior on scale { NumberAnimation { duration: Theme.animFast } }

            Image {
                id: glyph
                anchors.centerIn: parent
                width: 26
                height: 26
                sourceSize: Qt.size(52, 52)
                source: Icons.path(option.icon)
                visible: !option.primary
            }
            MultiEffect {
                anchors.fill: glyph
                source: glyph
                visible: option.primary
                colorization: 1
                colorizationColor: Theme.textOnGreen
                brightness: 1
            }
        }

        SText {
            id: caption
            anchors { horizontalCenter: parent.horizontalCenter; top: circle.bottom; topMargin: 12 }
            text: option.label
            size: 14
            weight: option.primary ? 600 : 450
            color: option.primary ? Theme.ink : Theme.inkSoft
        }

        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: option.clicked()
        }
    }
}
