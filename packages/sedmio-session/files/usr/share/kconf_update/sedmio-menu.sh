#!/bin/sh
# Меню программ сменилось (XDG_MENU_PREFIX plasma- → sedmio-), а кэш
# KService (ksycoca) пересобирается только при изменении файлов, не
# переменной — окно «Открыть с помощью» показывало бы старое дерево
# Plasma. Пересобрать один раз. В фоне: kded ждёт kconf_update.
[ "$XDG_MENU_PREFIX" = sedmio- ] || exit 0
kbuildsycoca6 --noincremental </dev/null >/dev/null 2>&1 &
exit 0
