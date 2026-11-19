#!/bin/sh
# Win+↑ / Win+↓ — действиям скрипта KWin sedmio-windowkeys (развернуть;
# вернуть размер или свернуть) вместо «прилепить к верху/низу». Win+Tab —
# обзору окон и рабочих столов, как «Представление задач» в Windows (был
# вторым Alt+Tab; Alt+Tab остаётся переключателем окон). Сочетания
# KWin живут только в ~/.config/kglobalshortcutsrc, а пока сеанс идёт, файл
# держит kglobalaccel — поэтому меняем через него по D-Bus.
# Трогаем клавишу, только если она стоит по умолчанию и скрипт загружен:
# иначе осталась бы ни за чем. Запускает kconf_update один раз при входе.

call() {
  busctl --user --timeout=5 call org.kde.kglobalaccel /kglobalaccel org.kde.KGlobalAccel "$@" 2>/dev/null
}

# Meta+Up = Qt::META | Qt::Key_Up, Meta+Down = Qt::META | Qt::Key_Down.
move() { # $1 — действие KWin, $2 — наше, $3 — клавиша
  [ "$(call shortcutKeys as 4 kwin "$1" "" "")" = "a(ai) 1 4 $3 0 0 0" ] || return 0
  call setForeignShortcutKeys "asa(ai)" 4 kwin "$1" "" "" 0 >/dev/null
  call setForeignShortcutKeys "asa(ai)" 4 kwin "$2" "" "" 1 4 "$3" 0 0 0 >/dev/null
}

run() {
  # KWin со скриптами обычно уже есть, но подождём.
  i=0
  until call allActionsForComponent as 1 kwin | grep -q "Sedmio Window Up"; do
    i=$((i + 1))
    [ $i -ge 30 ] && return 0   # скрипт выключен или KWin не тот — не трогаем
    sleep 1
  done
  move "Window Quick Tile Top" "Sedmio Window Up" 285212691
  move "Window Quick Tile Bottom" "Sedmio Window Down" 285212693
  # Meta+Tab = Qt::META | Qt::Key_Tab, Alt+Tab, Meta+W — у обзора по умолчанию.
  if [ "$(call shortcutKeys as 4 kwin "Walk Through Windows" "" "")" = "a(ai) 2 4 285212673 0 0 0 4 150994945 0 0 0" ] \
    && [ "$(call shortcutKeys as 4 kwin Overview "" "")" = "a(ai) 1 4 268435543 0 0 0" ]; then
    call setForeignShortcutKeys "asa(ai)" 4 kwin "Walk Through Windows" "" "" 1 4 150994945 0 0 0 >/dev/null
    call setForeignShortcutKeys "asa(ai)" 4 kwin Overview "" "" 2 4 268435543 0 0 0 4 285212673 0 0 0 >/dev/null
  fi
}

# В фоне: kded ждёт kconf_update, прежде чем грузить модули (трей и т. п.),
# — не держать его, пока ждём KWin.
run </dev/null >/dev/null 2>&1 &
exit 0
