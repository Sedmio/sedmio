#!/bin/sh
# Клавиша Пуска — только Win (Meta), как в sedmio-launcher.desktop.
# kglobalaccel отдаёт занятую клавишу тому, кто занял её первым, а на
# системе, где раньше работала Plasma, Win записан за меню plasmashell —
# забираем, только если у меню клавиши по умолчанию (Win, Alt+F1).
# Прежние версии добавляли Пуску Alt+F1, Alt+Пробел, Alt+F2, Search,
# Win+R и Win+S, а Win+A вызывал его же — убираем. Win+R тогда забирали у
# Spectacle (запись области; у него оставался Win+Shift+R) — возвращаем,
# если у него так и остался один Win+Shift+R. Не встало — повтор при
# следующем входе. Запускает kconf_update один раз при входе (Id в .upd).

call() {
  busctl --user --timeout=5 call org.kde.kglobalaccel /kglobalaccel org.kde.KGlobalAccel "$@" 2>/dev/null
}

launcher="sedmio-launcher.desktop"
meta=16777250           # Qt::Key_Meta — Win сам по себе (так его хранит kglobalaccel)
alt_f1=150994992        # Qt::ALT | Qt::Key_F1
meta_r=268435538        # Qt::META | Qt::Key_R
meta_shift_r=301989970  # Qt::META | Qt::SHIFT | Qt::Key_R
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

# Группы клавиш по строке, по порядку (kglobalaccel может вернуть их в
# другом порядке, чем назначали).
# Win бывает записан и с модификатором (Qt::META | Qt::Key_Meta) — к одному виду.
sorted_groups() { # $@ — «4 k 0 0 0 …»
  while [ $# -ge 5 ]; do echo "$1 $2 $3 $4 $5"; shift 5; done \
    | sed "s/^4 285212706 /4 $meta /" | sort
}

# Кто держит клавишу: пусто — никто, иначе строка actionList.
owner() { # $1 — клавиша
  case "$(call actionList "(ai)" 4 "$1" 0 0 0)" in
    "as 0") ;;
    "as "*) call actionList "(ai)" 4 "$1" 0 0 0 ;;
    *) return 1 ;;
  esac
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

  # Win у меню plasmashell по умолчанию — снять.
  plasma=$(keys_of plasmashell "$plasma_menu")
  # shellcheck disable=SC2086
  if [ -n "$plasma" ] && [ "$(sorted_groups $plasma)" = "$(sorted_groups 4 $meta 0 0 0 4 $alt_f1 0 0 0)" ]; then
    call setForeignShortcutKeys "asa(ai)" 4 plasmashell "$plasma_menu" "" "" 0 >/dev/null
  fi

  # У Пуска — только Win. Занят чем-то ещё (пользователь назначил) — у
  # Пуска клавиш нет, чужое не трогаем.
  who=$(owner $meta) || { retry; return 0; }
  case "$who" in
    "" | *"\"$launcher\""*)
      call setForeignShortcutKeys "asa(ai)" 4 "$launcher" _launch "" "" 1 4 $meta 0 0 0 >/dev/null ;;
    *)
      call setForeignShortcutKeys "asa(ai)" 4 "$launcher" _launch "" "" 0 >/dev/null ;;
  esac
  case "$(keys_of "$launcher" _launch)" in
    "" | "4 $meta 0 0 0" | "4 285212706 0 0 0") ;;
    *) retry ;;
  esac

  # Win+A вызывал Пуск через sedmio-control.desktop — файла больше нет.
  call unregister ss sedmio-control.desktop _launch >/dev/null

  # Win+R — вернуть Spectacle (запись области), если у него остался один
  # Win+Shift+R, а Win+R теперь свободен.
  if [ "$(keys_of org.kde.spectacle.desktop RecordRegion)" = "4 $meta_shift_r 0 0 0" ] && [ -z "$(owner $meta_r)" ]; then
    call setForeignShortcutKeys "asa(ai)" 4 org.kde.spectacle.desktop RecordRegion "" "" 2 4 $meta_shift_r 0 0 0 4 $meta_r 0 0 0 >/dev/null
  fi
}

# Повторить при следующем входе: снять отметку kconf_update.
retry() {
  kwriteconfig6 --file kconf_updaterc --group sedmio-launcherkeys.upd --key done --delete
}

# В фоне: kded ждёт kconf_update, прежде чем грузить модули.
run </dev/null >/dev/null 2>&1 &
exit 0
