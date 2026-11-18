pragma Singleton
import QtQuick
import Quickshell

// Что сейчас показывает всплывающий индикатор (громкость, яркость,
// раскладка...). Запросы приходят от OsdServer (shell.qml): их шлют kded,
// powerdevil и KWin — раньше они шли в plasmashell.
Singleton {
    id: root

    property bool shown: false
    property string screenName: ""

    // "progress" — полоса с процентами, "message" — значок и подпись.
    property string mode: "progress"
    property string kind: ""
    property string icon: ""
    property int percent: 0
    property int maximum: 100
    property string text: ""

    function show() {
        screenName = ShellState.focusedScreen();
        shown = true;
        hideTimer.restart();
    }

    function hide() { shown = false; }

    function progress(kind, icon, percent, maximum, label) {
        // Ноль громкости — это «звук выключен», полоса тут ни к чему.
        if (percent <= 0 && (kind === "volume" || kind === "microphone" || kind === "mediaPlayer")) {
            message(kind, kind === "microphone" ? "microphone-sensitivity-muted" : "audio-volume-muted",
                    kind === "microphone" ? "Микрофон выключен"
                    : kind === "mediaPlayer" ? label + ": без звука" : "Звук выключен");
            return;
        }

        root.mode = "progress";
        root.kind = kind;
        root.percent = percent;
        root.maximum = Math.max(1, maximum);
        root.text = label;
        root.icon = icon !== "" ? icon : progressIcon(kind, percent);
        show();
    }

    function message(kind, icon, text) {
        root.mode = "message";
        root.kind = kind;
        root.icon = icon;
        root.text = text;
        show();
    }

    function toggled(kind, enabled) {
        const texts = {
            touchpad: ["Тачпад включён", "Тачпад выключен", "input-touchpad-on", "input-touchpad-off"],
            wifi: ["Wi‑Fi включён", "Wi‑Fi выключен", "network-wireless-on", "network-wireless-off"],
            bluetooth: ["Bluetooth включён", "Bluetooth выключен", "preferences-system-bluetooth", "preferences-system-bluetooth-inactive"],
            wwan: ["Мобильный интернет включён", "Мобильный интернет выключен", "network-mobile-on", "network-mobile-off"],
            virtualKeyboard: ["Экранная клавиатура включена", "Экранная клавиатура выключена", "input-keyboard-virtual-on", "input-keyboard-virtual-off"],
            inhibited: ["Сон и блокировка запрещены", "Сон и блокировка разрешены", "system-suspend-inhibited", "system-suspend-uninhibited"],
        };
        const t = texts[kind];
        if (!t) return;
        message(kind, enabled ? t[2] : t[3], enabled ? t[0] : t[1]);
    }

    function powerProfile(profile) {
        const profiles = {
            "power-saver": ["battery-profile-powersave", "Энергосбережение"],
            "balanced": ["speedometer", "Сбалансированный режим"],
            "performance": ["battery-profile-performance", "Производительность"],
        };
        const p = profiles[profile];
        if (p) message("powerProfile", p[0], p[1]);
    }

    function progressIcon(kind, percent) {
        switch (kind) {
        case "volume":
            return percent <= 25 ? "audio-volume-low" : percent <= 75 ? "audio-volume-medium"
                 : percent <= 100 ? "audio-volume-high" : "audio-volume-high-warning";
        case "microphone":
            return percent <= 25 ? "microphone-sensitivity-low" : percent <= 75
                 ? "microphone-sensitivity-medium" : "microphone-sensitivity-high";
        case "brightness":
            return "video-display-brightness";
        case "keyboardBrightness":
            return "input-keyboard-brightness";
        }
        return "";
    }

    Timer {
        id: hideTimer
        interval: 1600
        onTriggered: root.shown = false
    }
}
