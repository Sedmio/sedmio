#!/usr/bin/env bash
# Доводка установленной системы. Запускается Calamares после установки:
#   postinstall.sh <корень целевой системы>
set -euo pipefail

ROOT="${1:?не передан корень целевой системы}"
in_target() { arch-chroot "$ROOT" "$@"; }

# Правила NoExtract из sedmio-settings: не ставим переводы на другие языки.
if ! grep -q 'sedmio-options.conf' "$ROOT/etc/pacman.conf"; then
  sed -i '/^\[options\]/a Include = /etc/pacman.d/sedmio-options.conf' "$ROOT/etc/pacman.conf"
fi

# Консоль: русская раскладка и шрифт с кириллицей.
printf 'KEYMAP=ru\nFONT=cyr-sun16\n' > "$ROOT/etc/vconsole.conf"

# Службы из пресетов sedmio-base и профилей машины.
in_target systemctl preset-all

# Вход без пароля (переключатель на странице пользователя): Calamares
# кладёт такого пользователя в группу autologin. Экран входа — greetd
# (sedmio-login): сразу после включения запускаем сеанс этого
# пользователя, а выйдет — обычный экран входа.
# Без автовхода группы нет: getent выходит с кодом 2, и без «|| true»
# set -e молча обрывал бы весь скрипт.
autologin_user="$(in_target getent group autologin | cut -d: -f4 | cut -d, -f1)" || true
if [[ -n $autologin_user ]]; then
  cat >> "$ROOT/etc/greetd/sedmio.toml" <<TOML

# Вход без пароля (выбран при установке). Убрать — удалить эту секцию.
[initial_session]
command = "/usr/bin/sedmio-session"
user = "$autologin_user"
TOML
fi
