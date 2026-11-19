#!/bin/sh
# Клавиши запуска программ. Сначала — его собственные по умолчанию (Win,
# Alt+F1, Alt+Пробел, Alt+F2, Search из sedmio-launcher.desktop): kglobalaccel
# отдаёт занятую клавишу тому, кто занял её первым, а на системе, где
# раньше работала Plasma, Win и Alt+F1 записаны за меню plasmashell, — и
# запуск оставался без Win. Забираем их у plasmashell, только если там они
# по умолчанию и Plasma не выбрана вместо нашей оболочки (use-plasmashell,
# запасной путь). Потом Win+R («Выполнить») и Win+S (поиск). Win+R по
# умолчанию у Spectacle: запись области экрана (у неё есть и Win+Shift+R —
# его оставляем). Клавишу Spectacle забираем, только если у него
# сочетания по умолчанию; свободную — просто добавляем запуску. Занятую
# чем-то ещё (пользователь назначил) не трогаем. Не встало — возвращаем
# как было и повторяем при следующем входе. Запускает kconf_update один
# раз при входе (Id в .upd; новый Id — ещё раз у всех).

call() {
  busctl --user --timeout=5 call org.kde.kglobalaccel /kglobalaccel org.kde.KGlobalAccel "$@" 2>/dev/null
}

launcher="sedmio-launcher.desktop"
meta_r=268435538        # Qt::META | Qt::Key_R
meta_shift_r=301989970  # Qt::META | Qt::SHIFT | Qt::Key_R
meta_s=268435539        # Qt::META | Qt::Key_S
meta=16777250           # Qt::Key_Meta — Win сам по себе (так его хранит kglobalaccel)
alt_f1=150994992        # Qt::ALT | Qt::Key_F1
alt_space=134217760     # Qt::ALT | Qt::Key_Space
alt_f2=150994993        # Qt::ALT | Qt::Key_F2
search=16777362         # Qt::Key_Search
plasma_menu="activate application launcher"

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

# Группы клавиш по строке, по порядку (kglobalaccel может вернуть их в
# другом порядке, чем назначали).
# Win бывает записан и с модификатором (Qt::META | Qt::Key_Meta) — к одному виду.
sorted_groups() { # $@ — «4 k 0 0 0 …»
  while [ $# -ge 5 ]; do echo "$1 $2 $3 $4 $5"; shift 5; done \
    | sed "s/^4 285212706 /4 $meta /" | sort
}

# Win и Alt+F1 — у меню plasmashell по умолчанию: забрать запуску.
take_from_plasma() {
  [ -e "${XDG_CONFIG_HOME:-$HOME/.config}/sedmio/use-plasmashell" ] && return 0
  if [ -e "${XDG_RUNTIME_DIR:-/nonexistent}/sedmio/shell-fallback" ]; then
    retry   # сейчас работает запасной plasmashell — в другой раз
    return 0
  fi
  plasma=$(keys_of plasmashell "$plasma_menu") || return 0
  # shellcheck disable=SC2086
  [ "$(sorted_groups $plasma)" = "$(sorted_groups 4 $meta 0 0 0 4 $alt_f1 0 0 0)" ] || return 0
  groups=$(keys_of "$launcher" _launch) || { retry; return 0; }
  # shellcheck disable=SC2086
  set -- $groups
  [ $(($# % 5)) -eq 0 ] || return 0
  call setForeignShortcutKeys "asa(ai)" 4 plasmashell "$plasma_menu" "" "" 0 >/dev/null
  call setForeignShortcutKeys "asa(ai)" 4 "$launcher" _launch "" "" $(($# / 5 + 2)) "$@" 4 $meta 0 0 0 4 $alt_f1 0 0 0 >/dev/null
  if ! launcher_has $meta || ! launcher_has $alt_f1; then
    # Не встало — запуску как было, меню plasmashell его клавиши.
    call setForeignShortcutKeys "asa(ai)" 4 "$launcher" _launch "" "" $(($# / 5)) "$@" >/dev/null
    call setForeignShortcutKeys "asa(ai)" 4 plasmashell "$plasma_menu" "" "" 2 4 $meta 0 0 0 4 $alt_f1 0 0 0 >/dev/null
    retry
  fi
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
  take_from_plasma
  for key in $meta $alt_f1 $alt_space $alt_f2 $search; do
    add $key
    [ $? -ne 1 ] || retry
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
