import QtQuick
import QtQuick.Particles
import io.calamares.core 1.0
import io.calamares.ui 1.0
import "components"

// Финал. Успех: седум зацветает, над ним летает пыльца.
// Ошибка: растение остаётся без цветов, показываем подробности.
// config: модуль finished (failed, failureMessage, failureDetails, doRestart).
SPage {
    id: page

    stage: 7
    blooming: !config.failed

    function onActivate() { page.replayAppear() }
    function onLeave() {}

    PageHeader {
        width: parent.width
        eyebrow: config.failed ? "Ошибка установки" : "Готово"
        title: config.failed ? "Что-то пошло не так" : "Sedmio выросла"
        subtitle: config.failed
                  ? config.failureMessage
                  : "Система установлена. Извлеките флешку и перезагрузите компьютер."
    }

    Card {
        width: parent.width
        padding: 16
        visible: config.failed && config.failureDetails !== ""

        TextEdit {
            width: parent.width
            text: config.failureDetails
            readOnly: true
            selectByMouse: true
            wrapMode: TextEdit.Wrap
            font.family: "JetBrains Mono"
            font.pixelSize: Theme.fontSmall
            color: Theme.inkSoft
            selectionColor: Theme.leafLight
        }
    }

    Row {
        spacing: 8

        SButton {
            primary: true
            visible: !config.failed
            text: "Перезагрузить"
            onClicked: config.doRestart(true)
        }
        SButton {
            text: "Закрыть"
            onClicked: ViewManager.quit()
        }
    }

    // Пыльца: редкие золотые искорки, которые ветерок сносит с цветов
    ParticleSystem {
        id: pollen
        running: !config.failed && page.visible
    }
    Emitter {
        system: pollen
        parent: page.plant
        anchors.centerIn: parent
        width: parent.width * 0.6
        height: parent.height * 0.6
        shape: EllipseShape {}
        enabled: !config.failed
        emitRate: 2.2
        lifeSpan: 4200
        lifeSpanVariation: 1200
        velocity: AngleDirection { angle: 300; angleVariation: 35; magnitude: 13; magnitudeVariation: 7 }
        acceleration: PointDirection { x: 2; y: -3; xVariation: 5; yVariation: 3 }
    }
    ItemParticle {
        system: pollen
        parent: page.plant
        anchors.fill: parent
        fade: true
        delegate: Item {
            readonly property real core: 2.2 + Math.random() * 2
            width: core
            height: core
            // мягкое свечение и светлая сердцевина
            Rectangle {
                anchors.centerIn: parent
                width: parent.core * 3.2
                height: width
                radius: width / 2
                color: Theme.bloom
                opacity: 0.22
            }
            Rectangle {
                anchors.centerIn: parent
                width: parent.core
                height: width
                radius: width / 2
                color: Theme.flowerPale
            }
        }
    }
}
