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

# Профиль машины: батарея есть — ноутбук.
if compgen -G '/sys/class/power_supply/BAT*' > /dev/null; then
  host=sedmio-host-laptop
else
  host=sedmio-host-desktop
fi
echo "Профиль машины: $host"
# TODO: ставить пакет профиля, когда репозиторий [sedmio] появится
#       в целевой системе (пока он есть только локально в out/repo).
# in_target pacman -S --noconfirm --needed "$host"

# Службы из пресетов sedmio-base и профилей машины.
in_target systemctl preset-all
