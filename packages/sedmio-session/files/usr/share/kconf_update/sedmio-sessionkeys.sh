#!/bin/sh
# Клавиши сеанса — нашим действиям в /usr/share/kglobalaccel вместо
# компонентов Plasma (модули kded из plasma-workspace):
#   Ctrl+Alt+Del          sedmio-logout.desktop  ← ksmserver «Log Out»
#   Meta+L, Screensaver   sedmio-lock.desktop    ← ksmserver «Lock Session»
#   клавиши мультимедиа   sedmio-media.desktop   ← mediacontrol
# Без Plasma её компоненты пропадут, а клавиши останутся записанными за
# ними. Забираем, только если у действия Plasma ровно его клавиши по
# умолчанию (пользователь не менял); свободные — просто нашему; занятые
# чем-то ещё не трогаем. Не встало — возвращаем как было и повторяем при
# следующем входе.

call() {
  busctl --user --timeout=5 call org.kde.kglobalaccel /kglobalaccel org.kde.KGlobalAccel "$@" 2>/dev/null
}

failed=

# Аргументы setForeignShortcutKeys для набора клавиш.
keys_args() {
  r="$#"
  for k; do r="$r 4 $k 0 0 0"; done
  echo "$r"
}

set_keys() { # компонент действие клавиши…
  c=$1 a=$2; shift 2
  # shellcheck disable=SC2046
  call setForeignShortcutKeys "asa(ai)" 4 "$c" "$a" "" "" $(keys_args "$@") >/dev/null
}

# Наш компонент kglobalaccel читает при старте — подождём.
wait_for() { # компонент действие
  i=0
  until call allActionsForComponent as 1 "$1" | grep -q "\"$2\""; do
    i=$((i + 1))
    [ $i -lt 30 ] || return 1
    sleep 1
  done
}

# Клавиши действия списком: «K1 K2».
keys_of() { # компонент действие
  call shortcutKeys as 4 "$1" "$2" "" "" | awk '{for (i = 4; i <= NF; i += 5) printf "%s ", $i}'
}

has_all() { # «список» клавиши… — все клавиши есть в списке
  l=" $1 "; shift
  for k; do
    case "$l" in *" $k "*) ;; *) return 1 ;; esac
  done
}

same() { # «список» клавиши… — в списке ровно эти клавиши (порядок любой)
  # shellcheck disable=SC2086
  [ "$(set -- $1; echo $#)" -eq $(($# - 1)) ] && has_all "$@"
}

# Чья клавиша на деле: shortcutKeys у нашего действия показывает и
# клавиши, которые kglobalaccel не дал (заняты), — верить только actionList.
owner() { # клавиша
  call actionList "(ai)" 4 "$1" 0 0 0
}

owned() { # компонент действие клавиши… — печатает те, что у действия
  c=$1 a=$2; shift 2
  for k; do
    case "$(owner "$k")" in *"\"$c\" \"$a\""*) printf "%s " "$k" ;; esac
  done
}

move() { # наш_компонент действие компонент_Plasma действие_Plasma клавиши…
  comp=$1 action=$2 from=$3 fromaction=$4; shift 4
  if ! wait_for "$comp" "$action"; then
    # Пакет поставили в открытом сеансе — повторим при следующем входе.
    [ -f "/usr/share/kglobalaccel/$comp" ] && failed=1
    return
  fi
  # Свои клавиши (не из Plasma, например Toggle Media Play/Pause) у
  # нашего действия остаются.
  # shellcheck disable=SC2046
  mine=$(owned "$comp" "$action" $(keys_of "$comp" "$action"))
  has_all "$mine" "$@" && return

  if same "$(keys_of "$from" "$fromaction")" "$@" && [ -n "$(owned "$from" "$fromaction" "$@")" ]; then
    set_keys "$from" "$fromaction"
    # shellcheck disable=SC2086
    set_keys "$comp" "$action" $mine "$@"
    has_all "$(owned "$comp" "$action" "$@")" "$@" && return
    set_keys "$from" "$fromaction" "$@"
    failed=1
    return
  fi

  # У Plasma клавиши поменяли (или её нет) — нашему только свободные.
  free=
  for k; do
    o=$(owner "$k") || { failed=1; return; }
    [ "$o" = "as 0" ] && free="$free $k"
  done
  [ -n "$free" ] || return
  # shellcheck disable=SC2086
  set_keys "$comp" "$action" $mine $free
}

run() {
  move sedmio-logout.desktop _launch ksmserver "Log Out" 218103815   # Ctrl+Alt+Del
  move sedmio-lock.desktop _launch ksmserver "Lock Session" 16777402 268435532   # Screensaver, Meta+L
  m=sedmio-media.desktop
  move $m PlayPause mediacontrol playpausemedia 16777344   # Media Play
  move $m Pause mediacontrol pausemedia 16777349
  move $m Stop mediacontrol stopmedia 16777345
  move $m Previous mediacontrol previousmedia 16777346
  move $m Next mediacontrol nextmedia 16777347
  move $m Forward mediacontrol seekforwardmedia 16777474
  move $m Rewind mediacontrol seekbackwardmedia 16777413
  [ -z "$failed" ] || kwriteconfig6 --file kconf_updaterc --group sedmio-sessionkeys.upd --key done --delete
}

# В фоне: kded ждёт kconf_update, прежде чем грузить модули.
run </dev/null >/dev/null 2>&1 &
exit 0
