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

    // Подробности размечены для окна Calamares («Команда <i>…</i>»), но вывод
    // команды внутри не экранирован, поэтому убираем только теги разметки,
    // а не всё в угловых скобках (иначе пропадёт «<vda>» из вывода).
    function plain(html) {
        return (html || "").replace(/<br\s*\/?>/gi, "\n")
                           .replace(/<\/?(i|b|u|em|strong|code|pre|tt)>/gi, "")
                           .replace(/&lt;/g, "<").replace(/&gt;/g, ">")
                           .replace(/&quot;/g, "\"").replace(/&amp;/g, "&").trim()
    }

    Card {
        width: parent.width
        padding: 16
        visible: config.failed && config.failureDetails !== ""

        // Вывод команды бывает длинным. Причина ошибки обычно в последних
        // строках, поэтому карточка открывается прокрученной к концу.
        Item {
            width: parent.width
            height: Math.min(details.implicitHeight, 168)

            Flickable {
                id: detailsView
                anchors.fill: parent
                contentHeight: details.implicitHeight
                contentY: Math.max(0, contentHeight - height)
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                TextEdit {
                    id: details
                    width: parent.width
                    text: page.plain(config.failureDetails)
                    readOnly: true
                    selectByMouse: true
                    wrapMode: TextEdit.Wrap
                    font.family: "JetBrains Mono"
                    font.pixelSize: Theme.fontSmall
                    color: Theme.inkSoft
                    selectionColor: Theme.leafLight
                }
            }

            ScrollFade { view: detailsView; atTop: true; tint: Theme.surface }
            ScrollFade { view: detailsView; tint: Theme.surface }
        }
    }

    Text {
        width: parent.width
        visible: config.failed
        text: "Полный журнал: /home/live/.cache/calamares/session.log"
        wrapMode: Text.Wrap
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSmall
        color: Theme.inkMuted
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
            primary: config.failed
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
