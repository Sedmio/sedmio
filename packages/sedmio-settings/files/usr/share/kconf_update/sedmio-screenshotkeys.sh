#!/bin/sh
# PrtSc и Win+Shift+S (снимок области) и Win+PrtSc (весь экран) — нашему
# sedmio-screenshot.desktop: сразу в буфер и в папку, как в Windows 11,
# вместо Spectacle (открывает своё окно; Win+PrtSc у него — активное окно). Обе программы просят эти клавиши в .desktop, и kglobalaccel
# отдаёт их тому, кто раньше попался, — так что передаём явно, по D-Bus.
# Трогаем, только если у Spectacle клавиши по умолчанию: свои пользователя
# не перебиваем. Запускает kconf_update один раз при входе.

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

# Meta+Shift+S = Qt::META | Qt::SHIFT | Qt::Key_S, Print = Qt::Key_Print.
keys="2 4 301989971 0 0 0 4 16777225 0 0 0"

run() {
  # kglobalaccel узнаёт о программах из .desktop при запуске — подождём.
  i=0
  until actions=$(call allActionsForComponent as 1 sedmio-screenshot.desktop) \
    && case "$actions" in *'"_launch"'*'"Screen"'* | *'"Screen"'*'"_launch"'*) true ;; *) false ;; esac; do
    i=$((i + 1))
    [ $i -ge 30 ] && break
    sleep 1
  done
  case "$actions" in
    *'"_launch"'*) ;;
    *)
      # Файл есть, но kglobalaccel его ещё не прочёл (пакет поставили в
      # открытом сеансе) — повторить при следующем входе. Файла нет — не трогаем.
      [ -e /usr/share/kglobalaccel/sedmio-screenshot.desktop ] \
        && kwriteconfig6 --file kconf_updaterc --group sedmio-screenshotkeys.upd --key done --delete
      return 0 ;;
  esac

  retry=
  if has org.kde.spectacle.desktop _launch "$keys"; then
    give org.kde.spectacle.desktop _launch sedmio-screenshot.desktop _launch "$keys"
  fi

  case "$actions" in
    *'"Screen"'*) ;;
    *)
      # Пакет обновили в открытом сеансе: kglobalaccel помнит старый
      # .desktop, без «Screen». Повторить при следующем входе — снять
      # отметку kconf_update (всё здесь можно выполнять повторно).
      kwriteconfig6 --file kconf_updaterc --group sedmio-screenshotkeys.upd --key done --delete
      return 0 ;;
  esac
  # Meta+Print = Qt::META | Qt::Key_Print.
  if has org.kde.spectacle.desktop ActiveWindowScreenShot "1 4 285212681 0 0 0"; then
    give org.kde.spectacle.desktop ActiveWindowScreenShot sedmio-screenshot.desktop Screen "1 4 285212681 0 0 0"
  fi
  [ -z "$retry" ] || kwriteconfig6 --file kconf_updaterc --group sedmio-screenshotkeys.upd --key done --delete
}

# В фоне: kded ждёт kconf_update, прежде чем грузить модули.
run </dev/null >/dev/null 2>&1 &
exit 0
