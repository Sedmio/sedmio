import QtCore
import QtQuick
import org.kde.plasma.private.sessions as Sessions
import "file:///usr/share/sedmio/login-ui"

// Экран блокировки Sedmio (его загружает LockScreen.qml).
Item {
    id: root

    // Пишет kscreenlocker_greet (через LockScreen.qml).
    property bool locked: false
    property bool viewVisible: false

    implicitWidth: 800
    implicitHeight: 600

    // Обои пользователя, размытые: ссылку на картинку держат «Параметры».
    Backdrop {
        anchors.fill: parent
        image: StandardPaths.writableLocation(StandardPaths.GenericStateLocation) + "/sedmio/wallpaper"
        dimmed: true
    }

    Sessions.SessionManagement { id: session }

    ClockBlock {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: card.top
        anchors.bottomMargin: Math.max(40, root.height * 0.07)
    }

    LoginCard {
        id: card
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: root.height * 0.08

        displayName: kscreenlocker_userName
        avatar: kscreenlocker_userImage !== ""
            ? "file://" + kscreenlocker_userImage.split("/").map(encodeURIComponent).join("/") : ""
        busy: LockState.busy
        message: LockState.message
        messageIsError: LockState.messageIsError

        onSubmitted: text => LockState.submit(text)
        onEdited: LockState.edited()
        onPasswordChanged: LockState.password = password

        Binding on password { value: LockState.password }
    }

    Connections {
        target: LockState
        function onRejectionsChanged() { card.rejected(); }
    }

    Row {
        anchors { right: parent.right; bottom: parent.bottom; margins: 28 }
        spacing: 12
        LayoutChip {}
        RoundButton {
            visible: session.canSuspend
            icon: "system-suspend"
            label: "Сон"
            onClicked: session.suspend()
        }
    }

    onViewVisibleChanged: if (viewVisible) card.focusInput()
    Component.onCompleted: card.focusInput()
}
