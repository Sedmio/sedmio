#!/bin/sh
# На системе, где раньше работала Plasma, kglobalaccel помнит клавиши
# plasmashell: Win+1…9 (панель задач), Win+V (журнал буфера обмена), Win+A
# (комнаты в старых версиях). Занятую клавишу он отдаёт тому, кто занял её
# первым, и наши действия (/usr/share/kglobalaccel/sedmio-*.desktop) с теми
# же клавишами по умолчанию оставались без них. Забираем: только если у
# действия plasmashell ровно эта одна клавиша (не назначал ли пользователь
# своё) и Plasma не выбрана вместо нашей оболочки (use-plasmashell,
# запасной путь). Свободную клавишу — просто нашему действию. Занятую чем-то
# ещё не трогаем. Не встало — возвращаем как было и повторяем при
# следующем входе. Win и Alt+F1 у меню plasmashell забирает
# sedmio-launcherkeys. Запускает kconf_update один раз при входе.

call() {
  busctl --user --timeout=5 call org.kde.kglobalaccel /kglobalaccel org.kde.KGlobalAccel "$@" 2>/dev/null
}

retry() {
  kwriteconfig6 --file kconf_updaterc --group sedmio-plasmakeys.upd --key done --delete
}

# Клавиши действия группами «4 k 0 0 0 …» (без «a(ai) N»); нет клавиш — пусто.
keys_of() { # $1 — компонент, $2 — действие
  cur=$(call shortcutKeys as 4 "$1" "$2" "" "") || return 1
  case "$cur" in
    "a(ai) 0") ;;
    "a(ai) "*) printf '%s\n' "${cur#a(ai) * }" ;;
    *) return 1 ;;
  esac
}

has_key() { # $1 — компонент, $2 — действие, $3 — клавиша
  case " $(keys_of "$1" "$2") " in *" 4 $3 0 0 0 "*) return 0 ;; esac
  return 1
}

# take КЛАВИША КОМПОНЕНТ ДЕЙСТВИЕ ДЕЙСТВИЕ_PLASMASHELL
take() {
  key=$1 comp=$2 action=$3 plasma=$4
  owner=$(call actionList "(ai)" 4 "$key" 0 0 0) || { retry; return 0; }
  case "$owner" in
    "as 0") from= ;;
    *"\"$comp\" \"$action\""*) return 0 ;;
    *"\"plasmashell\" \"$plasma\""*)
      [ "$(keys_of plasmashell "$plasma")" = "4 $key 0 0 0" ] || return 0
      from=1 ;;
    *) return 0 ;;
  esac
  ours=$(keys_of "$comp" "$action") || { retry; return 0; }
  # shellcheck disable=SC2086
  set -- $ours
  [ $(($# % 5)) -eq 0 ] || return 0
  [ -z "$from" ] || call setForeignShortcutKeys "asa(ai)" 4 plasmashell "$plasma" "" "" 0 >/dev/null
  call setForeignShortcutKeys "asa(ai)" 4 "$comp" "$action" "" "" $(($# / 5 + 1)) "$@" 4 "$key" 0 0 0 >/dev/null
  has_key "$comp" "$action" "$key" && return 0
  call setForeignShortcutKeys "asa(ai)" 4 "$comp" "$action" "" "" $(($# / 5)) "$@" >/dev/null
  [ -z "$from" ] || call setForeignShortcutKeys "asa(ai)" 4 plasmashell "$plasma" "" "" 1 4 "$key" 0 0 0 >/dev/null
  retry
}

run() {
  [ -e "${XDG_CONFIG_HOME:-$HOME/.config}/sedmio/use-plasmashell" ] && return 0
  if [ -e "${XDG_RUNTIME_DIR:-/nonexistent}/sedmio/shell-fallback" ]; then
    retry   # сейчас работает запасной plasmashell — в другой раз
    return 0
  fi
  # Наши действия kglobalaccel читает при старте — подождём.
  i=0
  until call allActionsForComponent as 1 sedmio-windows.desktop | grep -q '"_launch"'; do
    i=$((i + 1))
    if [ $i -ge 30 ]; then
      [ -f /usr/share/kglobalaccel/sedmio-windows.desktop ] && retry
      return 0
    fi
    sleep 1
  done

  # Win+1…9 = Qt::META | Qt::Key_1…9; первая — действие _launch, остальные — «2»…«9».
  n=1
  while [ $n -le 9 ]; do
    action=$n
    [ $n -eq 1 ] && action=_launch
    take $((268435504 + n)) sedmio-windows.desktop "$action" "activate task manager entry $n"
    n=$((n + 1))
  done
  take 268435542 sedmio-clipboard.desktop _launch show-on-mouse-pos   # Win+V
  take 268435521 sedmio-control.desktop _launch "next activity"       # Win+A
}

# В фоне: kded ждёт kconf_update, прежде чем грузить модули.
run </dev/null >/dev/null 2>&1 &
exit 0
