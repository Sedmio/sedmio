#!/bin/sh
# Схема цветов Sedmio (/usr/share/color-schemes/Sedmio.colors) вместо
# Breeze — если пользователь сам схему не выбирал. Plasma берёт схему
# только из ~/.config/kdeglobals, умолчание в /etc/xdg она не видит.
# Запускает kconf_update один раз при входе в сеанс.
[ -r /usr/share/color-schemes/Sedmio.colors ] || exit 0

conf="${XDG_CONFIG_HOME:-$HOME/.config}/kdeglobals"
current=$(kreadconfig6 --file "$conf" --group General --key ColorScheme 2>/dev/null)
case $current in
  ""|BreezeLight|Breeze) ;;
  *) exit 0 ;;   # выбрана своя — не трогаем
esac

# Применить сразу (и сообщить запущенным программам). Не вышло — хотя бы
# записать выбор: при следующем входе Plasma применит схему сама.
plasma-apply-colorscheme Sedmio >/dev/null 2>&1 ||
  kwriteconfig6 --file "$conf" --group General --key ColorScheme Sedmio
exit 0
