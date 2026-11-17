import QtQuick
import "components"

// Экран во время установки (slideshowAPI: 2). Calamares загружает файл
// при старте и вызывает onActivate()/onLeave().
// Слева — медленно вращающийся седум, справа — сменяющиеся подсказки.
Rectangle {
    id: show

    property bool activatedInCalamares: false
    property int current: 0

    readonly property var slides: [
        { title: "Как привычно",
          text: "Окна, сочетания клавиш, переключение языка и буфер обмена работают так, как вы привыкли в Windows." },
        { title: "Готова к играм",
          text: "Ядро CachyOS с планировщиком под игры, пакеты под Zen 4 и свежие драйверы NVIDIA и AMD." },
        { title: "Всё на русском",
          text: "Интерфейс, форматы дат и раскладки настроены сразу. Alt+Shift переключает язык." },
        { title: "Есть запасной выход",
          text: "Если обновление что-то сломает, выберите в меню загрузки запасное ядро — система загрузится." },
        { title: "Одна система на всё",
          text: "Настройки приходят обновлениями: поменяли в одном месте — получили на всех своих компьютерах." }
    ]

    function onActivate() {
        current = 0
        activatedInCalamares = true
        sedum.regrow(5)
    }
    function onLeave() {
        activatedInCalamares = false
    }

    color: Theme.paper

    Timer {
        interval: 7000
        repeat: true
        running: show.activatedInCalamares
        onTriggered: show.current = (show.current + 1) % show.slides.length
    }

    Item {
        id: plantArea
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: parent.width * 0.48

        Backdrop { anchors.fill: parent }

        Sedum {
            id: sedum
            anchors.centerIn: parent
            size: Math.min(plantArea.width, plantArea.height) * 0.9
            stage: 6
        }
    }

    Item {
        anchors.left: plantArea.right
        anchors.right: parent.right
        anchors.rightMargin: Theme.sideMargin
        anchors.verticalCenter: parent.verticalCenter
        height: 220

        Repeater {
            model: show.slides

            delegate: Column {
                readonly property bool active: index === show.current

                width: parent.width
                spacing: 14
                opacity: active ? 1 : 0
                x: active ? 0 : 24
                Behavior on opacity { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
                Behavior on x { SpringAnimation { spring: 2; damping: 0.3 } }

                Text {
                    text: "0" + (index + 1) + " / 0" + show.slides.length
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSmall
                    font.weight: Font.DemiBold
                    font.letterSpacing: 1
                    color: Theme.terracotta
                }
                Text {
                    width: parent.width
                    text: modelData.title
                    wrapMode: Text.WordWrap
                    font.family: Theme.fontFamily
                    font.pixelSize: 38
                    font.weight: Font.DemiBold
                    font.letterSpacing: Theme.titleTracking
                    color: Theme.ink
                }
                Text {
                    width: parent.width
                    text: modelData.text
                    wrapMode: Text.WordWrap
                    lineHeight: 1.3
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontLarge
                    color: Theme.inkSoft
                }
            }
        }
    }
}
