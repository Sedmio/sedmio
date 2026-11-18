import QtQuick

// Экран блокировки Sedmio. Его показывает kscreenlocker_greet (KWin
// запускает его при блокировке), пакет выбран переменной
// PLASMA_DEFAULT_SHELL (usr/lib/environment.d/60-sedmio-lockscreen.conf).
//
// Защита от поломки: наш экран (SedmioLock.qml) не загрузился — нет
// модуля после обновления, ошибка в QML — показываем стандартный экран
// блокировки Plasma. А если и этот файл не загрузится, kscreenlocker
// подставит свой встроенный. Сеанс при этом заблокирован всегда: его
// держит KWin, а не этот экран.
Item {
    id: root

    // Пишет kscreenlocker_greet; передаём загруженному экрану.
    property bool locked: false
    property bool viewVisible: false

    implicitWidth: 800
    implicitHeight: 600

    Loader {
        id: screen
        anchors.fill: parent
        focus: true
        source: "SedmioLock.qml"
        onStatusChanged: {
            if (status === Loader.Error && source.toString().indexOf("SedmioLock") >= 0) {
                console.warn("Sedmio: экран блокировки не загрузился, показываю стандартный Plasma");
                source = "file:///usr/share/plasma/shells/org.kde.plasma.desktop/contents/lockscreen/LockScreen.qml";
            }
        }
    }

    Binding { target: screen.item; property: "locked"; value: root.locked; when: screen.item !== null }
    Binding { target: screen.item; property: "viewVisible"; value: root.viewVisible; when: screen.item !== null }
}
