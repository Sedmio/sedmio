#!/bin/sh
# PrtSc и Win+Shift+S — нашему sedmio-screenshot.desktop (снимок области
# сразу в буфер и в папку, как в Windows 11) вместо Spectacle (открывает
# своё окно). Обе программы просят эти клавиши в .desktop, и kglobalaccel
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
  until call allActionsForComponent as 1 sedmio-screenshot.desktop | grep -q '"_launch"'; do
    i=$((i + 1))
    [ $i -ge 30 ] && return 0   # нашего .desktop нет — ничего не трогаем
    sleep 1
  done
  [ "$(call shortcutKeys as 4 org.kde.spectacle.desktop _launch "" "")" = "a(ai) $keys" ] || return 0
  call setForeignShortcutKeys "asa(ai)" 4 org.kde.spectacle.desktop _launch "" "" 0 >/dev/null
  # shellcheck disable=SC2086
  call setForeignShortcutKeys "asa(ai)" 4 sedmio-screenshot.desktop _launch "" "" $keys >/dev/null
}

# В фоне: kded ждёт kconf_update, прежде чем грузить модули.
run </dev/null >/dev/null 2>&1 &
exit 0
