#!/bin/sh
# Ctrl+Alt+Del — экрану «Что сделать?» Sedmio (sedmio-logout.desktop рядом
# в /usr/share/kglobalaccel). На системе с Plasma эту клавишу держит её
# компонент ksmserver («Log Out», модуль kded из plasma-workspace); без
# Plasma он пропадёт, а клавиша осталась бы записанной за ним. Забираем,
# только если у его действия ровно эта клавиша (пользователь не менял);
# свободную — просто нашему; занятую чем-то ещё не трогаем. Не встало —
# возвращаем как было и повторяем при следующем входе.

call() {
  busctl --user --timeout=5 call org.kde.kglobalaccel /kglobalaccel org.kde.KGlobalAccel "$@" 2>/dev/null
}

retry() {
  kwriteconfig6 --file kconf_updaterc --group sedmio-sessionkeys.upd --key done --delete
}

key=218103815   # Qt::CTRL | Qt::ALT | Qt::Key_Delete
comp=sedmio-logout.desktop
action=_launch

run() {
  # Наше действие kglobalaccel читает при старте — подождём. Пакет
  # поставили в открытом сеансе — повторим при следующем входе.
  i=0
  until call allActionsForComponent as 1 "$comp" | grep -q "\"$action\""; do
    i=$((i + 1))
    if [ $i -ge 30 ]; then
      [ -f "/usr/share/kglobalaccel/$comp" ] && retry
      return 0
    fi
    sleep 1
  done

  owner=$(call actionList "(ai)" 4 $key 0 0 0) || { retry; return 0; }
  case "$owner" in
    *"\"$comp\" \"$action\""*) return 0 ;;
    "as 0") from= ;;
    *'"ksmserver" "Log Out"'*)
      [ "$(call shortcutKeys as 4 ksmserver "Log Out" "" "")" = "a(ai) 1 4 $key 0 0 0" ] || return 0
      from=1 ;;
    *) return 0 ;;
  esac
  [ -z "$from" ] || call setForeignShortcutKeys "asa(ai)" 4 ksmserver "Log Out" "" "" 0 >/dev/null
  call setForeignShortcutKeys "asa(ai)" 4 "$comp" "$action" "" "" 1 4 $key 0 0 0 >/dev/null
  [ "$(call shortcutKeys as 4 "$comp" "$action" "" "")" = "a(ai) 1 4 $key 0 0 0" ] && return 0
  [ -z "$from" ] || call setForeignShortcutKeys "asa(ai)" 4 ksmserver "Log Out" "" "" 1 4 $key 0 0 0 >/dev/null
  retry
}

# В фоне: kded ждёт kconf_update, прежде чем грузить модули.
run </dev/null >/dev/null 2>&1 &
exit 0
