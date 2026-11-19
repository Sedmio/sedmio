#!/bin/sh
# Win+↑ / Win+↓ — действиям скрипта KWin sedmio-windowkeys (развернуть;
# вернуть размер или свернуть) вместо «прилепить к верху/низу». Win+Tab —
# обзору окон и рабочих столов, как «Представление задач» в Windows (был
# вторым Alt+Tab; Alt+Tab остаётся переключателем окон). Alt+F4 — действию
# скрипта: закрывает окно, как раньше, а на пустом рабочем столе открывает
# «Что сделать?». Ctrl+F1…F4 — программам (Ctrl+F4 закрывает вкладку или
# документ), а не переходу на рабочий стол 1…4: у него остаются Win+F1…F4.
# Сочетания
# KWin живут только в ~/.config/kglobalshortcutsrc, а пока сеанс идёт, файл
# держит kglobalaccel — поэтому меняем через него по D-Bus.
# Трогаем клавишу, только если она стоит по умолчанию и скрипт загружен:
# иначе осталась бы ни за чем. Запускает kconf_update один раз при входе.

call() {
  busctl --user --timeout=5 call org.kde.kglobalaccel /kglobalaccel org.kde.KGlobalAccel "$@" 2>/dev/null
}

# Клавиши из ответа «a(ai) N 4 k 0 0 0 …» — по группе в строке, по порядку
# (kglobalaccel может вернуть их в другом порядке, чем назначали).
groups() {
  # shellcheck disable=SC2086
  set -- $1
  [ $# -ge 2 ] || return 0
  shift 2
  while [ $# -ge 5 ]; do echo "$1 $2 $3 $4 $5"; shift 5; done | sort
}

has() { # $1 $2 — компонент и действие, $3 — «N 4 k 0 0 0 …»: у действия ровно эти клавиши
  [ "$(groups "$(call shortcutKeys as 4 "$1" "$2" "" "")")" = "$(groups "a(ai) $3")" ]
}

# Передать клавиши $5 от действия $1 $2 действию $3 $4. Не встали (kglobalaccel
# не ответил) — вернуть прежнему, чтобы клавиши не остались ни за чем, и
# повторить при следующем входе.
give() {
  call setForeignShortcutKeys "asa(ai)" 4 "$1" "$2" "" "" 0 >/dev/null
  # shellcheck disable=SC2086
  call setForeignShortcutKeys "asa(ai)" 4 "$3" "$4" "" "" $5 >/dev/null
  has "$3" "$4" "$5" && return 0
  # shellcheck disable=SC2086
  call setForeignShortcutKeys "asa(ai)" 4 "$1" "$2" "" "" $5 >/dev/null
  retry=1
}

# Meta+Up = Qt::META | Qt::Key_Up, Meta+Down = Qt::META | Qt::Key_Down.
# Нашего действия ещё нет (пакет обновили в открытом сеансе, KWin не
# перечитал скрипт) — клавишу не трогаем, иначе она осталась бы ни за чем,
# а повторяем при следующем входе (retry).
move() { # $1 — действие KWin, $2 — наше, $3 — клавиша
  has kwin "$1" "1 4 $3 0 0 0" || return 0
  case "$actions" in *"\"$2\""*) ;; *) retry=1; return 0 ;; esac
  give kwin "$1" kwin "$2" "1 4 $3 0 0 0"
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
  if has kwin "Walk Through Windows" "2 4 285212673 0 0 0 4 150994945 0 0 0" \
    && has kwin Overview "1 4 268435543 0 0 0"; then
    call setForeignShortcutKeys "asa(ai)" 4 kwin "Walk Through Windows" "" "" 1 4 150994945 0 0 0 >/dev/null
    call setForeignShortcutKeys "asa(ai)" 4 kwin Overview "" "" 2 4 268435543 0 0 0 4 285212673 0 0 0 >/dev/null
    # Обзор не взял Win+Tab — вернуть перебору окон, как было.
    if ! has kwin Overview "2 4 268435543 0 0 0 4 285212673 0 0 0"; then
      call setForeignShortcutKeys "asa(ai)" 4 kwin Overview "" "" 1 4 268435543 0 0 0 >/dev/null
      call setForeignShortcutKeys "asa(ai)" 4 kwin "Walk Through Windows" "" "" 2 4 285212673 0 0 0 4 150994945 0 0 0 >/dev/null
      retry=1
    fi
  fi
  # Ctrl+F1…F4 и Win+F1…F4 у «перейти на рабочий стол N» по умолчанию —
  # оставить только Win+F1…F4. Снять клавишу не может «наполовину» — откат
  # не нужен; не ответил kglobalaccel — повторим.
  n=1
  while [ $n -le 4 ]; do
    ctrl=$((83886127 + n))   # Qt::CTRL | Qt::Key_F1…F4
    meta=$((285212719 + n))  # Qt::META | Qt::Key_F1…F4
    if has kwin "Switch to Desktop $n" "2 4 $ctrl 0 0 0 4 $meta 0 0 0"; then
      call setForeignShortcutKeys "asa(ai)" 4 kwin "Switch to Desktop $n" "" "" 1 4 $meta 0 0 0 >/dev/null
      has kwin "Switch to Desktop $n" "1 4 $meta 0 0 0" || retry=1
    fi
    n=$((n + 1))
  done
  # Повторить при следующем входе: снять отметку kconf_update.
  [ -z "$retry" ] || kwriteconfig6 --file kconf_updaterc --group sedmio-windowkeys.upd --key done --delete
}

# В фоне: kded ждёт kconf_update, прежде чем грузить модули (трей и т. п.),
# — не держать его, пока ждём KWin.
run </dev/null >/dev/null 2>&1 &
exit 0
