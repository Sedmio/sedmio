#!/bin/sh
# Win+↑ / Win+↓ — действиям скрипта KWin sedmio-windowkeys (развернуть;
# вернуть размер или свернуть) вместо «прилепить к верху/низу». Win+Tab —
# обзору окон и рабочих столов, как «Представление задач» в Windows (был
# вторым Alt+Tab; Alt+Tab остаётся переключателем окон). Alt+F4 — действию
# скрипта: закрывает окно, как раньше, а на пустом рабочем столе открывает
# «Что сделать?». Сочетания
# KWin живут только в ~/.config/kglobalshortcutsrc, а пока сеанс идёт, файл
# держит kglobalaccel — поэтому меняем через него по D-Bus.
# Трогаем клавишу, только если она стоит по умолчанию и скрипт загружен:
# иначе осталась бы ни за чем. Запускает kconf_update один раз при входе.

call() {
  busctl --user --timeout=5 call org.kde.kglobalaccel /kglobalaccel org.kde.KGlobalAccel "$@" 2>/dev/null
}

# Meta+Up = Qt::META | Qt::Key_Up, Meta+Down = Qt::META | Qt::Key_Down.
# Нашего действия ещё нет (пакет обновили в открытом сеансе, KWin не
# перечитал скрипт) — клавишу не трогаем, иначе она осталась бы ни за чем,
# а повторяем при следующем входе (retry).
move() { # $1 — действие KWin, $2 — наше, $3 — клавиша
  [ "$(call shortcutKeys as 4 kwin "$1" "" "")" = "a(ai) 1 4 $3 0 0 0" ] || return 0
  case "$actions" in *"\"$2\""*) ;; *) retry=1; return 0 ;; esac
  call setForeignShortcutKeys "asa(ai)" 4 kwin "$1" "" "" 0 >/dev/null
  call setForeignShortcutKeys "asa(ai)" 4 kwin "$2" "" "" 1 4 "$3" 0 0 0 >/dev/null
}

run() {
  # KWin со скриптами обычно уже есть, но подождём.
  i=0
  until actions=$(call allActionsForComponent as 1 kwin) \
    && case "$actions" in *'"Sedmio Window Up"'*) true ;; *) false ;; esac; do
    i=$((i + 1))
    if [ $i -ge 30 ]; then
      # Скрипт есть и не выключен, но KWin его ещё не загрузил (пакет
      # поставили в открытом сеансе) — повторить при следующем входе.
      # Выключен или его нет — не трогаем.
      [ -d /usr/share/kwin/scripts/sedmio-windowkeys ] \
        && [ "$(kreadconfig6 --file kwinrc --group Plugins --key sedmio-windowkeysEnabled --default true)" != false ] \
        && kwriteconfig6 --file kconf_updaterc --group sedmio-windowkeys.upd --key done --delete
      return 0
    fi
    sleep 1
  done
  retry=
  move "Window Quick Tile Top" "Sedmio Window Up" 285212691
  move "Window Quick Tile Bottom" "Sedmio Window Down" 285212693
  move "Window Close" "Sedmio Window Close" 150994995   # Alt+F4
  # Meta+Tab = Qt::META | Qt::Key_Tab, Alt+Tab, Meta+W — у обзора по умолчанию.
  if [ "$(call shortcutKeys as 4 kwin "Walk Through Windows" "" "")" = "a(ai) 2 4 285212673 0 0 0 4 150994945 0 0 0" ] \
    && [ "$(call shortcutKeys as 4 kwin Overview "" "")" = "a(ai) 1 4 268435543 0 0 0" ]; then
    call setForeignShortcutKeys "asa(ai)" 4 kwin "Walk Through Windows" "" "" 1 4 150994945 0 0 0 >/dev/null
    call setForeignShortcutKeys "asa(ai)" 4 kwin Overview "" "" 2 4 268435543 0 0 0 4 285212673 0 0 0 >/dev/null
  fi
  # Повторить при следующем входе: снять отметку kconf_update.
  [ -z "$retry" ] || kwriteconfig6 --file kconf_updaterc --group sedmio-windowkeys.upd --key done --delete
}

# В фоне: kded ждёт kconf_update, прежде чем грузить модули (трей и т. п.),
# — не держать его, пока ждём KWin.
run </dev/null >/dev/null 2>&1 &
exit 0
