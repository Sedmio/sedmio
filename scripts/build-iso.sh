#!/usr/bin/env bash
# Собирает ISO: свежий профиль releng из archiso + дополнения из iso/.
# Перед этим нужно собрать пакеты: scripts/build-packages.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$ROOT/out/repo"
OUT="$ROOT/out/iso"
WORK="$ROOT/work/iso"
PROFILE="$WORK/profile"
RELENG=/usr/share/archiso/configs/releng
NOEXTRACT="$ROOT/packages/sedmio-settings/files/etc/pacman.d/sedmio-options.conf"

if [[ $EUID -ne 0 ]]; then
  echo "Запусти через sudo: mkarchiso требует root." >&2
  exit 1
fi
if [[ ! -d $RELENG ]]; then
  echo "Не найден $RELENG. Установи archiso: pacman -S archiso" >&2
  exit 1
fi
if [[ ! -f $REPO/sedmio.db ]]; then
  echo "Нет локального репозитория. Сначала: scripts/build-packages.sh" >&2
  exit 1
fi

rm -rf "$WORK"
mkdir -p "$WORK" "$OUT"
cp -r "$RELENG" "$PROFILE"

# Название образа
sed -i \
  -e 's/^iso_name=.*/iso_name="sedmio"/' \
  -e 's/^iso_label="ARCH_/iso_label="SEDMIO_/' \
  -e 's|^iso_publisher=.*|iso_publisher="Sedmio <https://github.com/Sedmio>"|' \
  -e 's/^iso_application=.*/iso_application="Sedmio Linux"/' \
  "$PROFILE/profiledef.sh"

# Репозитории: как на машине сборки (CachyOS + multilib) + наш локальный.
# Правила NoExtract уменьшают образ: не кладём переводы на другие языки.
cp /etc/pacman.conf "$PROFILE/pacman.conf"
sed -i "/^\[options\]/a Include = $NOEXTRACT" "$PROFILE/pacman.conf"
cat >> "$PROFILE/pacman.conf" <<EOF

[sedmio]
SigLevel = Optional TrustAll
Server = file://$REPO
EOF

# Пакеты и файлы live-системы
cat "$ROOT/iso/packages.x86_64" >> "$PROFILE/packages.x86_64"
if [[ -d $ROOT/iso/airootfs ]]; then
  cp -a "$ROOT/iso/airootfs/." "$PROFILE/airootfs/"
fi

mkarchiso -v -w "$WORK/build" -o "$OUT" "$PROFILE"

echo
echo "Готово: $OUT"
