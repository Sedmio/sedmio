import QtCore
import QtQuick
import "file:///usr/share/sedmio/login-ui"

// Заставка при входе (ksplashqml, тема выбрана в /etc/xdg/ksplashrc).
// Фон — те же обои, что у оболочки и экранов входа и блокировки: после
// экрана входа (он гаснет в бумагу) и до рабочего стола всё одного цвета.
// В середине — знак и тонкая полоса загрузки; к концу они гаснут, и
// рабочий стол появляется без скачка.
//
// stage от ksplash: 1…5 по мере запуска сеанса, на 6-й окно закрывается.
// Не загрузится эта тема — ksplash возьмёт запасную (Breeze), а сам
// закроется не позже чем через 30 секунд.
Backdrop {
    id: root
    property int stage
    // Обои пользователя, как на рабочем столе (ссылку держат «Параметры»).
    image: StandardPaths.writableLocation(StandardPaths.GenericStateLocation) + "/sedmio/wallpaper"

    Column {
        id: center
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -20
        spacing: 28
        opacity: 0
        Component.onCompleted: opacity = 1
        Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }

        Connections {
            target: root
            function onStageChanged() { if (root.stage >= 5) center.opacity = 0; }
        }

        Image {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 96
            height: 96
            sourceSize: Qt.size(192, 192)
            source: "file:///usr/share/icons/hicolor/scalable/apps/sedmio.svg"
        }

        // Полоса загрузки: растёт по этапам ksplash.
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 160
            height: 4
            radius: 2
            color: Qt.rgba(Theme.green.r, Theme.green.g, Theme.green.b, 0.15)

            Rectangle {
                height: parent.height
                radius: 2
                color: Theme.green
                width: parent.width * Math.min(1, Math.max(0.08, root.stage / 5))
                Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
            }
        }
    }
}
