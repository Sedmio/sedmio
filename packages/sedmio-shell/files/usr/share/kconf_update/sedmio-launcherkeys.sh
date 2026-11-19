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

# Клавиши действия группами «4 k 0 0 0 …» (без «a(ai) N»); нет клавиш — пусто.
keys_of() { # $1 — компонент, $2 — действие
  cur=$(call shortcutKeys as 4 "$1" "$2" "" "") || return 1
  case "$cur" in
    "a(ai) 0") ;;
    "a(ai) "*) printf '%s\n' "${cur#a(ai) * }" ;;
    *) return 1 ;;
  esac
}

launcher_has() { # $1 — клавиша
  case " $(keys_of "$launcher" _launch) " in *" 4 $1 0 0 0 "*) return 0 ;; esac
  return 1
}

# Добавить клавишу запуску, если она свободна. 0 — клавиша у запуска,
# 1 — не получилось (kglobalaccel не ответил), 2 — занята другим, не трогаем.
add() { # $1 — клавиша
  case "$(call actionList "(ai)" 4 "$1" 0 0 0)" in
    "as 0") ;;
    *"\"$launcher\""*) return 0 ;;
    "as "*) return 2 ;;
    *) return 1 ;;
  esac
  groups=$(keys_of "$launcher" _launch) || return 1
  # shellcheck disable=SC2086
  set -- "$1" $groups
  key=$1; shift
  [ $(($# % 5)) -eq 0 ] || return 1   # не тот формат — не трогаем
  call setForeignShortcutKeys "asa(ai)" 4 "$launcher" _launch "" "" $(($# / 5 + 1)) "$@" 4 "$key" 0 0 0 >/dev/null
  launcher_has "$key"
}

run() {
  i=0
  until call allActionsForComponent as 1 "$launcher" | grep -q '"_launch"'; do
    i=$((i + 1))
    if [ $i -ge 30 ]; then
      # Оболочка есть, а kglobalaccel о ней ещё не знает (пакет поставили в
      # открытом сеансе) — повторить при следующем входе. Нет её — не трогаем.
      [ -f /usr/share/kglobalaccel/$launcher ] && retry
      return 0
    fi
    sleep 1
  done
  # По умолчанию у Spectacle Meta+Shift+R и Meta+R (порядок бывает любой).
  case "$(call shortcutKeys as 4 org.kde.spectacle.desktop RecordRegion "" "")" in
    "a(ai) 2 4 $meta_shift_r 0 0 0 4 $meta_r 0 0 0" | "a(ai) 2 4 $meta_r 0 0 0 4 $meta_shift_r 0 0 0") spectacle_default=1 ;;
    *) spectacle_default= ;;
  esac
  if [ -n "$spectacle_default" ]; then
    call setForeignShortcutKeys "asa(ai)" 4 org.kde.spectacle.desktop RecordRegion "" "" 1 4 $meta_shift_r 0 0 0 >/dev/null
    # Не встала у запуска — вернуть Spectacle, чтобы клавиша не осталась ни за чем.
    if ! add $meta_r; then
      call setForeignShortcutKeys "asa(ai)" 4 org.kde.spectacle.desktop RecordRegion "" "" 2 4 $meta_shift_r 0 0 0 4 $meta_r 0 0 0 >/dev/null
      retry
    fi
  else
    add $meta_r
    [ $? -ne 1 ] || retry
  fi
  add $meta_s
  [ $? -ne 1 ] || retry
}

# Повторить при следующем входе: снять отметку kconf_update.
retry() {
  kwriteconfig6 --file kconf_updaterc --group sedmio-launcherkeys.upd --key done --delete
}

# В фоне: kded ждёт kconf_update, прежде чем грузить модули.
run </dev/null >/dev/null 2>&1 &
exit 0
