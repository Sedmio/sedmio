#!/bin/sh
# Alt+Shift и Ctrl+Shift — переключение языка как в Windows. Параметр xkb
# grp:alt_shift_toggle переключает в момент нажатия: Alt+Shift+Tab (окна
# назад) или Ctrl+Shift+T в браузере меняли язык. Сочетание KWin из одних
# модификаторов срабатывает по отпусканию и только если между ними не
# нажали другую клавишу; работает и на экране блокировки.
#
# Переводим: назначаем сочетание действию KWin «следующая раскладка»
# (к его Meta+Alt+K), проверяем, что встало, и только потом убираем
# параметр xkb у пользователя — иначе язык переключался бы дважды (то есть
# никак) или не переключался вовсе. Экран входа (свой KWin, без наших
# клавиш) остаётся на xkb: /etc/xdg/kxkbrc не трогаем. «Параметры» потом
# делают то же, когда выбирают способ переключения (метка SwitchKey).
# Запускает kconf_update один раз при входе.

call() {
  busctl --user --timeout=5 call org.kde.kglobalaccel /kglobalaccel org.kde.KGlobalAccel "$@" 2>/dev/null
}
component="KDE Keyboard Layout Switcher"
action="Switch to Next Keyboard Layout"

run() {
  options=$(kreadconfig6 --file kxkbrc --group Layout --key Options)
  case ",$options," in
    *,grp:alt_shift_toggle,*) grp=grp:alt_shift_toggle id=alt_shift key=150994976 ;;   # Qt::ALT | Qt::Key_Shift
    *,grp:ctrl_shift_toggle,*) grp=grp:ctrl_shift_toggle id=ctrl_shift key=83886112 ;; # Qt::CTRL | Qt::Key_Shift
    *) return 0 ;;   # другое переключение (Win+Пробел, Caps Lock) — оставляем xkb
  esac

  # Действие появляется, когда KWin загрузил раскладки, — подождём.
  i=0
  until call allActionsForComponent as 1 "$component" | grep -q "\"$action\""; do
    i=$((i + 1))
    [ $i -ge 30 ] && return 0   # нет — xkb остаётся, язык переключается как раньше
    sleep 1
  done
  cur=$(call shortcutKeys as 4 "$component" "$action" "" "") || return 0
  # «a(ai) N 4 k 0 0 0 …» → группы без нашей клавиши, плюс она.
  set -- $(printf '%s\n' "${cur#a(ai) * }" | sed "s/ *4 $key 0 0 0//")
  case "$cur" in "a(ai) 0") set -- ;; esac
  [ $(($# % 5)) -eq 0 ] || return 0
  # shellcheck disable=SC2068
  call setForeignShortcutKeys "asa(ai)" 4 "$component" "$action" "" "" $(($# / 5 + 1)) $@ 4 "$key" 0 0 0 >/dev/null
  case "$(call shortcutKeys as 4 "$component" "$action" "" "")" in
    *" 4 $key 0 0 0"*) ;;
    *) return 0 ;;   # не встало — xkb остаётся, язык переключается как раньше
  esac

  rest=$(printf '%s\n' "$options" | tr ',' '\n' | grep -vx "$grp" | paste -sd, -)
  kwriteconfig6 --notify --file kxkbrc --group Layout --key Options "$rest"
  kwriteconfig6 --file kxkbrc --group Layout --key SwitchKey "$id"
  # KWin перечитывает раскладки по этому сигналу.
  dbus-send --session --type=signal /Layouts org.kde.keyboard.reloadConfig
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
