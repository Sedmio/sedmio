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
  case "$actions" in *'"_launch"'*) ;; *) return 0 ;; esac   # нашего .desktop нет — не трогаем

  if [ "$(call shortcutKeys as 4 org.kde.spectacle.desktop _launch "" "")" = "a(ai) $keys" ]; then
    call setForeignShortcutKeys "asa(ai)" 4 org.kde.spectacle.desktop _launch "" "" 0 >/dev/null
    # shellcheck disable=SC2086
    call setForeignShortcutKeys "asa(ai)" 4 sedmio-screenshot.desktop _launch "" "" $keys >/dev/null
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
  if [ "$(call shortcutKeys as 4 org.kde.spectacle.desktop ActiveWindowScreenShot "" "")" = "a(ai) 1 4 285212681 0 0 0" ]; then
    call setForeignShortcutKeys "asa(ai)" 4 org.kde.spectacle.desktop ActiveWindowScreenShot "" "" 0 >/dev/null
    call setForeignShortcutKeys "asa(ai)" 4 sedmio-screenshot.desktop Screen "" "" 1 4 285212681 0 0 0 >/dev/null
  fi
}

# В фоне: kded ждёт kconf_update, прежде чем грузить модули.
run </dev/null >/dev/null 2>&1 &
exit 0
