import QtQuick

// Окно экрана выхода на одном мониторе (слой поверх всего — manager.cpp).
// Вид — /usr/share/sedmio/logout/SedmioLogout.qml. Не загрузился (сломанное обновление, нет модуля цветов)
// — простой встроенный Fallback.qml: выключить компьютер должно
// получаться всегда.
Window {
    id: win
    color: "transparent"
    flags: Qt.FramelessWindowHint

    Loader {
        id: screen
        anchors.fill: parent
        focus: true
        source: "file:///usr/share/sedmio/logout/SedmioLogout.qml"
        onStatusChanged: {
            if (status === Loader.Error && source.toString().indexOf("Fallback") < 0) {
                console.warn("sedmio-session-manager: экран выхода не загрузился, показываю простой");
                source = "Fallback.qml";
            }
        }
    }

    Connections {
        target: screen.item
        ignoreUnknownSignals: true
        function onLogoutRequested() { manager.logoutRequested(); }
        function onHaltRequested() { manager.haltRequested(); }
        function onHaltUpdateRequested() { manager.haltRequested(); }
        function onRebootRequested() { manager.rebootRequested(); }
        function onRebootRequested2(opt) { manager.rebootRequested(); }
        function onRebootUpdateRequested() { manager.rebootRequested(); }
        function onSuspendRequested(method) { manager.suspendRequested(method); }
        function onLockScreenRequested() { manager.lockScreenRequested(); }
        function onCancelRequested() { manager.cancelRequested(); }
    }
}
