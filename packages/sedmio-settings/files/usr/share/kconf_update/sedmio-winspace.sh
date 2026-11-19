#!/bin/sh
# Win+Пробел — действию KWin «следующая раскладка», к его клавишам
# (Meta+Alt+K, Alt+Shift…). Только если сочетание ни за кем не закреплено.
# Не встало (kglobalaccel не ответил, KWin не загрузил раскладки) —
# повторить при следующем входе. С параметром xkb grp:win_space_toggle
# язык не переключается дважды: xkb забирает пробел себе, KWin его не видит.
# «Параметры» (sedmio-preferences) сохраняют Win+Пробел так же.
# Запускает kconf_update один раз при входе.

call() {
  busctl --user --timeout=5 call org.kde.kglobalaccel /kglobalaccel org.kde.KGlobalAccel "$@" 2>/dev/null
}
component="KDE Keyboard Layout Switcher"
action="Switch to Next Keyboard Layout"
key=268435488   # Qt::META | Qt::Key_Space

retry() {
  kwriteconfig6 --file kconf_updaterc --group sedmio-winspace.upd --key done --delete
}

run() {
  # Действие появляется, когда KWin загрузил раскладки, — подождём.
  i=0
  until call allActionsForComponent as 1 "$component" | grep -q "\"$action\""; do
    i=$((i + 1))
    if [ $i -ge 30 ]; then
      # Одна раскладка — переключать нечего, действия может и не быть:
      # повторим, когда раскладок станет больше.
      retry
      return 0
    fi
    sleep 1
  done
  cur=$(call shortcutKeys as 4 "$component" "$action" "" "") || { retry; return 0; }
  case "$cur" in *" 4 $key 0 0 0"*) return 0 ;; esac   # уже есть
  owner=$(call actionList "(ai)" 4 "$key" 0 0 0) || { retry; return 0; }
  [ "$owner" = "as 0" ] || return 0   # занято другим — не отнимаем

  # «a(ai) N 4 k 0 0 0 …» → те же группы плюс наша.
  # shellcheck disable=SC2086
  set -- ${cur#a(ai) }
  n=$1
  shift
  [ $# -eq $((n * 5)) ] || { retry; return 0; }
  # shellcheck disable=SC2068
  call setForeignShortcutKeys "asa(ai)" 4 "$component" "$action" "" "" $((n + 1)) $@ 4 "$key" 0 0 0 >/dev/null
  case "$(call shortcutKeys as 4 "$component" "$action" "" "")" in
    *" 4 $key 0 0 0"*) ;;
    *) retry ;;
  esac
}

# Клавиши «следующей раскладки» меняют и sedmio-layoutswitch, и
# sedmio-winspace (при первом входе — одновременно): прочитать и записать
# их — по очереди, иначе один затрёт добавленное другим.
locked() {
  if command -v flock >/dev/null 2>&1; then
    exec 9>"${XDG_RUNTIME_DIR:-/tmp}/sedmio-layoutkeys.lock"
    flock -w 120 9
  fi
  run
}

# В фоне: kded ждёт kconf_update, прежде чем грузить модули.
locked </dev/null >/dev/null 2>&1 &
exit 0
