#!/bin/sh
# Win+R («Выполнить») и Win+S (поиск) — нашему запуску программ. Win+R по
# умолчанию у Spectacle: запись области экрана (у неё есть и Win+Shift+R —
# его оставляем). Клавишу Spectacle забираем, только если у него
# сочетания по умолчанию; свободную — просто добавляем запуску, к его
# Meta, Alt+F1 и прочим. Занятую чем-то ещё (пользователь назначил) не
# трогаем. Запускает kconf_update один раз при входе.

call() {
  busctl --user --timeout=5 call org.kde.kglobalaccel /kglobalaccel org.kde.KGlobalAccel "$@" 2>/dev/null
}

launcher="sedmio-launcher.desktop"
meta_r=268435538        # Qt::META | Qt::Key_R
meta_shift_r=301989970  # Qt::META | Qt::SHIFT | Qt::Key_R
meta_s=268435539        # Qt::META | Qt::Key_S

add() { # $1 — клавиша; добавить запуску, если она свободна или уже его
  case "$(call actionList "(ai)" 4 "$1" 0 0 0)" in
    "as 0" | *"\"$launcher\""*) ;;
    *) return 0 ;;
  esac
  cur=$(call shortcutKeys as 4 "$launcher" _launch "" "") || return 0
  # «a(ai) N 4 k 0 0 0 …» → группы «4 k 0 0 0» без этой клавиши, плюс она.
  set -- "$1" $(printf '%s\n' "${cur#a(ai) * }" | sed "s/ *4 $1 0 0 0//")
  key=$1; shift
  [ $(($# % 5)) -eq 0 ] || return 0   # не тот формат — не трогаем
  # shellcheck disable=SC2068
  call setForeignShortcutKeys "asa(ai)" 4 "$launcher" _launch "" "" $(($# / 5 + 1)) $@ 4 "$key" 0 0 0 >/dev/null
}

run() {
  i=0
  until call allActionsForComponent as 1 "$launcher" | grep -q '"_launch"'; do
    i=$((i + 1))
    [ $i -ge 30 ] && return 0   # оболочки нет — ничего не трогаем
    sleep 1
  done
  if [ "$(call shortcutKeys as 4 org.kde.spectacle.desktop RecordRegion "" "")" = "a(ai) 2 4 $meta_shift_r 0 0 0 4 $meta_r 0 0 0" ]; then
    call setForeignShortcutKeys "asa(ai)" 4 org.kde.spectacle.desktop RecordRegion "" "" 1 4 $meta_shift_r 0 0 0 >/dev/null
  fi
  add $meta_r
  add $meta_s
}

# В фоне: kded ждёт kconf_update, прежде чем грузить модули.
run </dev/null >/dev/null 2>&1 &
exit 0
