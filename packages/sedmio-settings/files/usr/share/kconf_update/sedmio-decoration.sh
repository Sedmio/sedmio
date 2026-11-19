#!/bin/sh
# Рамки окон Sedmio (org.sedmio.decoration из sedmio-theme) вместо
# Breeze — если пользователь сам рамки не выбирал. Умолчание из /etc/xdg
# Plasma перекрывает своим (~/.config/kdedefaults из пакета оформления
# Breeze), поэтому пишем в ~/.config/kwinrc. Нет плагина — KWin сам
# рисует Breeze, так что запись ничего не ломает.
# Запускает kconf_update один раз при входе в сеанс.
conf="${XDG_CONFIG_HOME:-$HOME/.config}/kwinrc"
current=$(kreadconfig6 --file "$conf" --group org.kde.kdecoration2 --key library 2>/dev/null)
case $current in
  ""|org.kde.breeze) ;;
  *) exit 0 ;;   # выбраны свои — не трогаем
esac

kwriteconfig6 --file "$conf" --group org.kde.kdecoration2 --key library org.sedmio.decoration
# kconf_update запускает kded, а он стартует уже после KWin: без этого
# новый пользователь увидел бы Breeze до следующего входа.
dbus-send --session --type=method_call --dest=org.kde.KWin /KWin org.kde.KWin.reconfigure >/dev/null 2>&1
exit 0
