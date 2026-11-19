#!/bin/sh
# Схема цветов Sedmio (/usr/share/color-schemes/Sedmio.colors) вместо
# Breeze — если пользователь сам схему не выбирал. Программы KDE берут
# цвета только из ~/.config/kdeglobals, умолчание в /etc/xdg не видят.
# Запускает kconf_update один раз при входе в сеанс.
[ -r /usr/share/color-schemes/Sedmio.colors ] || exit 0

conf="${XDG_CONFIG_HOME:-$HOME/.config}/kdeglobals"
current=$(kreadconfig6 --file "$conf" --group General --key ColorScheme 2>/dev/null)
case $current in
  ""|BreezeLight|Breeze) ;;
  *) exit 0 ;;   # выбрана своя — не трогаем
esac

# Записать выбор и перенести цвета в kdeglobals (так программы KDE их
# видят) с сообщением запущенным программам — это делает sedmio-theme-sync
# (пакет sedmio-theme) для схемы Sedmio. Нет его — цвета перенесёт он же,
# когда появится; plasma-apply-colorscheme ушёл вместе с Plasma.
kwriteconfig6 --file "$conf" --group General --key ColorScheme Sedmio
command -v sedmio-theme-sync >/dev/null 2>&1 && sedmio-theme-sync --once >/dev/null 2>&1
exit 0
