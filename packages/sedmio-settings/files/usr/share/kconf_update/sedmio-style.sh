#!/bin/sh
# Стиль программ Qt — Darkly вместо Breeze, если пользователь сам стиль не
# выбирал (Плазма раньше писала widgetStyle=Breeze в ~/.config/kdeglobals).
# Запускает kconf_update один раз при входе в сеанс.
[ -e /usr/lib/qt6/plugins/styles/darkly6.so ] || exit 0

conf="${XDG_CONFIG_HOME:-$HOME/.config}/kdeglobals"
current=$(kreadconfig6 --file "$conf" --group KDE --key widgetStyle 2>/dev/null)
case $current in
  ""|Breeze|breeze) ;;
  *) exit 0 ;;   # выбран свой — не трогаем
esac
[ -z "$current" ] && exit 0   # не задан — действует /etc/xdg/kdeglobals

kwriteconfig6 --file "$conf" --group KDE --key widgetStyle Darkly
exit 0
