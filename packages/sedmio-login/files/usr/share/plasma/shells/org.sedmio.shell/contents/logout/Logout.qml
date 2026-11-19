import QtQuick

// Экран «Выключить / перезагрузить / выйти» окна выхода Plasma
// (ksmserver-logout-greeter). В сеансе Sedmio экран показывает
// sedmio-session-manager; это — запасной путь, пока Plasma в системе:
// шина поднимает окно Plasma, если нашей службы нет. Пакет выбран той же
// переменной PLASMA_DEFAULT_SHELL, что и экран блокировки.
//
// Вид общий с sedmio-session-manager (/usr/share/sedmio/logout).
// Защита от поломки: наш экран (SedmioLogout.qml) не загрузился —
// показываем стандартный экран Plasma. Сигналы — те, что ждёт
// ksmserver-logout-greeter; передаём их от загруженного экрана.
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

    Loader {
        id: screen
        anchors.fill: parent
        focus: true
        source: "file:///usr/share/sedmio/logout/SedmioLogout.qml"
        onStatusChanged: {
            if (status === Loader.Error && source.toString().indexOf("SedmioLogout") >= 0) {
                console.warn("Sedmio: экран выхода не загрузился, показываю стандартный Plasma");
                source = "file:///usr/share/plasma/shells/org.kde.plasma.desktop/contents/logout/Logout.qml";
            }
        }
    }

    Connections {
        target: screen.item
        ignoreUnknownSignals: true
        function onLogoutRequested() { root.logoutRequested(); }
        function onHaltRequested() { root.haltRequested(); }
        function onHaltUpdateRequested() { root.haltUpdateRequested(); }
        function onSuspendRequested(spdMethod) { root.suspendRequested(spdMethod); }
        function onRebootRequested() { root.rebootRequested(); }
        function onRebootRequested2(opt) { root.rebootRequested2(opt); }
        function onRebootUpdateRequested() { root.rebootUpdateRequested(); }
        function onCancelRequested() { root.cancelRequested(); }
        function onLockScreenRequested() { root.lockScreenRequested(); }
        function onCancelSoftwareUpdateRequested() { root.cancelSoftwareUpdateRequested(); }
    }
}
