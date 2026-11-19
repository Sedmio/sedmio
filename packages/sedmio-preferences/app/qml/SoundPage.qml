import QtQuick
import QtQuick.Window
import Sedmio.Preferences

// «Звук»: куда выводить и откуда брать звук, громкость, звук отдельных
// программ, режим звуковых карт. Всё применяется сразу.
Page {
    id: root
    title: "Звук"

    Sound {
        id: sound
        // Уровень микрофона — только пока окно активно: свёрнутое окно
        // на Wayland об этом не узнаёт, а микрофон зря занят.
        metering: root.Window.active
    }

    readonly property var output: sound.output
    readonly property var input: sound.input

    // Значок «выключить звук» + ползунок + проценты.
    component Volume: Row {
        id: volume
        property real value: 0
        property bool muted: false
        property bool microphone: false
        property bool enabled_: true
        signal moved(real value)
        signal toggleMute()

        spacing: 8
        opacity: enabled_ ? 1 : 0.45

        Rectangle {
            width: 32
            height: 32
            radius: 9
            anchors.verticalCenter: parent.verticalCenter
            color: muteArea.containsMouse ? Theme.paperDeep : "transparent"
            SIcon {
                anchors.centerIn: parent
                size: 22
                name: volume.microphone
                      ? (volume.muted ? "microphone-sensitivity-muted" : "microphone-sensitivity-high")
                      : (volume.muted || volume.value <= 0 ? "audio-volume-muted"
                         : volume.value < 0.34 ? "audio-volume-low"
                         : volume.value < 0.67 ? "audio-volume-medium" : "audio-volume-high")
            }
            MouseArea {
                id: muteArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: if (volume.enabled_) volume.toggleMute()
            }
        }
        SSlider {
            width: 170
            anchors.verticalCenter: parent.verticalCenter
            maximum: 1
            step: 0.05
            value: volume.muted ? 0 : volume.value
            enabled: volume.enabled_
            onMoved: value => { if (volume.enabled_) volume.moved(value); }
        }
        SText {
            width: 44
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignRight
            text: volume.muted ? "выкл." : Math.round(volume.value * 100) + " %"
            color: Theme.inkSoft
        }
    }

    SText {
        visible: !sound.ready
        width: parent.width
        text: "Звуковая служба не отвечает. Если звука нет совсем, перезайдите в систему."
        color: Theme.terracotta
        wrapMode: Text.Wrap
    }

    Card {
        title: "Вывод"
        visible: sound.ready
        Setting {
            label: "Устройство"
            hint: root.output.devices.length === 0 ? "Звуковых устройств не найдено" : ""
            last: root.output.devices.length === 0
            Choice {
                visible: root.output.devices.length > 0
                model: root.output.devices
                currentIndex: root.output.device
                onActivated: index => sound.selectDevice(false, index)
            }
        }
        Setting {
            visible: root.output.ports.length > 0
            label: "Разъём"
            Choice {
                model: root.output.ports
                currentIndex: root.output.port
                onActivated: index => sound.selectPort(false, index)
            }
        }
        Setting {
            visible: root.output.device >= 0
            label: "Громкость"
            Volume {
                value: root.output.volume
                muted: root.output.muted
                enabled_: root.output.writable
                onMoved: value => sound.setVolume(false, value)
                onToggleMute: sound.setMuted(false, !root.output.muted)
            }
        }
        Setting {
            visible: root.output.device >= 0
            last: true
            label: "Проверка"
            hint: "Короткий сигнал на выбранном устройстве"
            SButton {
                text: "Проверить звук"
                onClicked: sound.testOutput()
            }
        }
    }

    Card {
        title: "Микрофон"
        visible: sound.ready
        Setting {
            label: "Устройство"
            hint: root.input.devices.length === 0 ? "Микрофон не найден" : ""
            last: root.input.devices.length === 0
            Choice {
                visible: root.input.devices.length > 0
                model: root.input.devices
                currentIndex: root.input.device
                onActivated: index => sound.selectDevice(true, index)
            }
        }
        Setting {
            visible: root.input.ports.length > 0
            label: "Разъём"
            Choice {
                model: root.input.ports
                currentIndex: root.input.port
                onActivated: index => sound.selectPort(true, index)
            }
        }
        Setting {
            visible: root.input.device >= 0
            label: "Громкость"
            Volume {
                microphone: true
                value: root.input.volume
                muted: root.input.muted
                enabled_: root.input.writable
                onMoved: value => sound.setVolume(true, value)
                onToggleMute: sound.setMuted(true, !root.input.muted)
            }
        }
        Setting {
            visible: root.input.device >= 0
            last: true
            label: "Уровень"
            hint: root.input.muted ? "Микрофон выключен" : "Скажите что-нибудь — полоска покажет, слышно ли вас"
            Rectangle {
                width: 262
                height: 8
                radius: 4
                color: Theme.paperDeep
                Rectangle {
                    // Пик в линейной шкале почти всегда у нуля — корень
                    // ближе к тому, как громкость слышит человек.
                    width: root.input.muted ? 0 : parent.width * Math.sqrt(sound.level)
                    height: parent.height
                    radius: parent.radius
                    color: Theme.leaf
                    Behavior on width { NumberAnimation { duration: 80 } }
                }
            }
        }
    }

    Card {
        title: "Программы"
        visible: sound.ready
        Setting {
            visible: sound.apps.length === 0
            last: true
            label: "Сейчас звук не воспроизводит ни одна программа"
        }
        Repeater {
            model: sound.apps
            delegate: Setting {
                id: app
                required property var modelData
                required property int index
                label: modelData.title
                hint: modelData.subtitle
                last: index === sound.apps.length - 1
                Volume {
                    value: app.modelData.volume
                    muted: app.modelData.muted
                    onMoved: value => sound.setAppVolume(app.modelData.id, value)
                    onToggleMute: sound.setAppMuted(app.modelData.id, !app.modelData.muted)
                }
            }
        }
    }

    Card {
        title: "Звуковые карты"
        visible: sound.ready && sound.cards.length > 0
        Repeater {
            model: sound.cards
            delegate: Setting {
                id: cardRow
                required property var modelData
                required property int index
                label: modelData.title
                hint: index === 0 ? "Какие входы и выходы карты работают: например, HDMI вместо динамиков" : ""
                last: index === sound.cards.length - 1
                Choice {
                    model: cardRow.modelData.profiles
                    currentIndex: cardRow.modelData.profile
                    onActivated: i => sound.selectProfile(cardRow.index, i)
                }
            }
        }
    }

    SButton {
        text: "Ещё в параметрах KDE"
        onClicked: App.openKde("kcm_pulseaudio")
    }
}
