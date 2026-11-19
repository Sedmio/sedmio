#!/bin/sh
# Тема значков Sedmio (/usr/share/icons/sedmio — Breeze с белыми знаками
# на папках) вместо Breeze — если пользователь сам тему не выбирал.
# Умолчание из /etc/xdg Plasma перекрывает своим (~/.config/kdedefaults из
# пакета оформления Breeze), поэтому пишем в ~/.config/kdeglobals.
# Запускает kconf_update один раз при входе в сеанс.
[ -r /usr/share/icons/sedmio/index.theme ] || exit 0

conf="${XDG_CONFIG_HOME:-$HOME/.config}/kdeglobals"
current=$(kreadconfig6 --file "$conf" --group Icons --key Theme 2>/dev/null)
case $current in
  ""|breeze) ;;
  *) exit 0 ;;   # выбрана своя — не трогаем
esac

kwriteconfig6 --file "$conf" --group Icons --key Theme sedmio
exit 0
