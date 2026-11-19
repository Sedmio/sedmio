import QtQuick
import Sedmio.Preferences

// «Мышь и тачпад»: скорость указателя, повышенная точность, основная
// кнопка, прокрутка; у тачпада — касание вместо нажатия и отключение при
// наборе. Применяется сразу (KWin сам запоминает).
Page {
    id: root
    title: "Мышь и тачпад"

    Pointers { id: pointers }

    readonly property var mouse: pointers.mouse
    readonly property var touchpad: pointers.touchpad

    readonly property var scrollSpeeds: [0.5, 1, 1.5, 2, 3]
    readonly property var scrollLabels: ["Медленно", "Обычно", "Быстрее", "Быстро", "Очень быстро"]
    function scrollIndex(factor) {
        let best = 0;
        for (let i = 0; i < scrollSpeeds.length; ++i)
            if (Math.abs(scrollSpeeds[i] - factor) < Math.abs(scrollSpeeds[best] - factor)) best = i;
        return best;
    }

    SText {
        visible: !root.mouse.present && !root.touchpad.present
        width: parent.width
        text: pointers.error !== "" ? pointers.error : "Мышь и тачпад не найдены."
        color: Theme.inkMuted
        wrapMode: Text.Wrap
    }

    Card {
        visible: root.mouse.present === true
        title: "Мышь"
        Setting {
            visible: root.mouse.supportsPointerAcceleration === true
            label: "Скорость указателя"
            SSlider {
                width: 260
                maximum: 2
                step: 0.1
                value: (root.mouse.pointerAcceleration ?? 0) + 1
                onMoved: value => pointers.set("mouse", "pointerAcceleration", Math.round((value - 1) * 20) / 20)
            }
        }
        Setting {
            visible: root.mouse.supportsPointerAccelerationProfileAdaptive === true
            label: "Повышенная точность"
            hint: "Медленное движение — точнее, быстрое — дальше."
            SSwitch {
                checked: root.mouse.pointerAccelerationProfileAdaptive === true
                onToggled: pointers.set("mouse", checked ? "pointerAccelerationProfileFlat" : "pointerAccelerationProfileAdaptive", true)
            }
        }
        Setting {
            visible: root.mouse.supportsLeftHanded === true
            label: "Основная кнопка"
            Choice {
                model: ["Левая", "Правая (для левой руки)"]
                currentIndex: root.mouse.leftHanded === true ? 1 : 0
                onActivated: index => pointers.set("mouse", "leftHanded", index === 1)
            }
        }
        Setting {
            label: "Скорость прокрутки"
            Choice {
                model: root.scrollLabels
                currentIndex: root.scrollIndex(root.mouse.scrollFactor ?? 1)
                onActivated: index => pointers.set("mouse", "scrollFactor", root.scrollSpeeds[index])
            }
        }
        Setting {
            visible: root.mouse.supportsNaturalScroll === true
            last: true
            label: "Обратная прокрутка"
            hint: "Колесо от себя — страница вниз, как на телефоне."
            SSwitch {
                checked: root.mouse.naturalScroll === true
                onToggled: pointers.set("mouse", "naturalScroll", !checked)
            }
        }
    }

    Card {
        visible: root.touchpad.present === true
        title: "Тачпад"
        Setting {
            visible: root.touchpad.supportsDisableEvents === true
            label: "Тачпад включён"
            SSwitch {
                checked: root.touchpad.enabled !== false
                onToggled: pointers.set("touchpad", "enabled", !checked)
            }
        }
        Setting {
            visible: root.touchpad.supportsPointerAcceleration === true
            label: "Скорость указателя"
            SSlider {
                width: 260
                maximum: 2
                step: 0.1
                value: (root.touchpad.pointerAcceleration ?? 0) + 1
                onMoved: value => pointers.set("touchpad", "pointerAcceleration", Math.round((value - 1) * 20) / 20)
            }
        }
        Setting {
            visible: (root.touchpad.tapFingerCount ?? 0) > 0
            label: "Нажатие касанием"
            hint: "Лёгкое касание — щелчок, двумя пальцами — правый."
            SSwitch {
                checked: root.touchpad.tapToClick === true
                onToggled: pointers.set("touchpad", "tapToClick", !checked)
            }
        }
        Setting {
            visible: root.touchpad.supportsNaturalScroll === true
            label: "Обратная прокрутка"
            hint: "Пальцы вниз — страница вверх, как на телефоне."
            SSwitch {
                checked: root.touchpad.naturalScroll === true
                onToggled: pointers.set("touchpad", "naturalScroll", !checked)
            }
        }
        Setting {
            visible: root.touchpad.supportsDisableWhileTyping === true
            last: true
            label: "Отключать при наборе текста"
            hint: "Чтобы ладонь не сдвигала курсор."
            SSwitch {
                checked: root.touchpad.disableWhileTyping === true
                onToggled: pointers.set("touchpad", "disableWhileTyping", !checked)
            }
        }
    }

    SText {
        visible: pointers.error !== "" && (root.mouse.present || root.touchpad.present)
        width: parent.width
        text: pointers.error
        color: Theme.terracotta
        wrapMode: Text.Wrap
    }

    SButton {
        text: "Курсор и другое — в параметрах KDE"
        onClicked: App.openKde("kcm_mouse")
    }
}
