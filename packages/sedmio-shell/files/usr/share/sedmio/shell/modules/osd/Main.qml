import QtQuick
import Quickshell
import Quickshell.Services.Kde
import qs

// Служба индикаторов вместо plasmashell: имя на шине org.kde.plasmashell,
// объект /org/kde/osdService. Её вызывают kded (клавиши
// громкости, плееры), powerdevil (яркость), KWin (раскладка). Модуль
// выключили — служба уходит с шины, клавиши работают без плашки.
Scope {
    OsdServer {
        onProgress: (kind, icon, percent, maximum, label) => OsdState.progress(kind, icon, percent, maximum, label)
        onMessage: (kind, icon, text) => {
            if (kind === "powerProfile") OsdState.powerProfile(text);
            else OsdState.message(kind, icon, text);
        }
        onToggled: (kind, enabled) => OsdState.toggled(kind, enabled)
        onHideRequested: OsdState.hide()
    }

    Connections {
        target: ShellState
        function onOsdRequested(kind, icon, percent, maximum, label) {
            OsdState.progress(kind, icon, percent, maximum, label);
        }
    }
}
