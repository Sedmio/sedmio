#!/usr/bin/env bash
# Ставит систему Sedmio на диск, смонтированный Calamares:
#   pacstrap.sh <корень целевой системы>
#
# Пакеты берутся из репозиториев live-системы: CachyOS (znver4), Arch
# и [sedmio] — он лежит прямо на live-образе, в /opt/sedmio/repo.
set -euo pipefail

ROOT="${1:?не передан корень целевой системы}"

# Профиль машины: есть батарея — ноутбук.
if compgen -G '/sys/class/power_supply/BAT*' > /dev/null; then
  host=sedmio-host-laptop
else
  host=sedmio-host-desktop
fi
echo "Профиль машины: $host"

# -K: своё хранилище ключей в целевой системе (ключи Arch и CachyOS
#     берутся из live-системы).
# Без -c: пакеты скачиваются в кэш на целевом диске. Live-система живёт
# в оперативной памяти, и пара гигабайт пакетов туда не влезет.
# Языки распознавания текста (Spectacle → tesseract → tessdata) указаны
# здесь явно: поставщика виртуальной зависимости pacman выбирает только
# среди явных целей, иначе ставит первый по алфавиту (африкаанс).
pacstrap -K "$ROOT" \
  base linux-firmware sudo nano efibootmgr \
  cachyos-keyring cachyos-mirrorlist cachyos-v4-mirrorlist \
  tesseract-data-rus tesseract-data-eng \
  "$host"

# pacman.conf — как в live-системе, но без локального [sedmio]:
# на установленной системе его нет.
# TODO: подключить [sedmio], когда репозиторий появится в сети.
awk '
  /^\[sedmio\]/ { skip = 1; next }
  /^\[/         { skip = 0 }
  !skip
' /etc/pacman.conf > "$ROOT/etc/pacman.conf"

# Зеркала Arch — из live-системы (их выбрал reflector при загрузке).
cp /etc/pacman.d/mirrorlist "$ROOT/etc/pacman.d/mirrorlist"
