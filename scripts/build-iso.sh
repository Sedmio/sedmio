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

# Сжатие zstd вместо xz: образ чуть больше, зато собирается и грузится быстрее
sed -i "s/^airootfs_image_tool_options=.*/airootfs_image_tool_options=('-comp' 'zstd' '-Xcompression-level' '15' '-b' '1M')/" \
  "$PROFILE/profiledef.sh"

# Права на файлы live-системы из iso/airootfs
sed -i '/^file_permissions=(/a \
  ["/etc/sudoers.d/sedmio-live"]="0:0:440"\
  ["/usr/local/lib/sedmio-live/setup.sh"]="0:0:755"' "$PROFILE/profiledef.sh"

# Репозитории для сборки: как на машине сборки (CachyOS + multilib)
# плюс локальный [sedmio]. Правила NoExtract уменьшают образ:
# не кладём переводы на другие языки.
cp /etc/pacman.conf "$PROFILE/pacman.conf"
sed -i "/^\[options\]/a Include = $NOEXTRACT" "$PROFILE/pacman.conf"
cat >> "$PROFILE/pacman.conf" <<EOF

[sedmio]
SigLevel = Optional TrustAll
Server = file://$REPO
EOF

# Пакеты и файлы live-системы
grep -v '^\s*\(#\|$\)' "$ROOT/iso/packages.x86_64" >> "$PROFILE/packages.x86_64"
cp -a "$ROOT/iso/airootfs/." "$PROFILE/airootfs/"

# В live-системе [sedmio] лежит прямо на образе: из него установщик
# ставит пакеты Sedmio на диск.
mkdir -p "$PROFILE/airootfs/opt/sedmio/repo"
cp "$REPO"/*.pkg.tar.zst "$PROFILE/airootfs/opt/sedmio/repo/"
repo-add -q "$PROFILE/airootfs/opt/sedmio/repo/sedmio.db.tar.gz" \
  "$PROFILE/airootfs/opt/sedmio/repo/"*.pkg.tar.zst
sed -e "s|^Server = file://$REPO|Server = file:///opt/sedmio/repo|" \
    -e "s|^Include = $NOEXTRACT|Include = /etc/pacman.d/sedmio-options.conf|" \
    "$PROFILE/pacman.conf" > "$PROFILE/airootfs/etc/pacman.conf"

# Меню загрузки. UEFI: GRUB со своей темой (iso/grub) вместо systemd-boot
# из releng — тот не умеет ни картинок, ни кириллицы. BIOS: syslinux из
# releng, меняем только название и заставку (кириллицы он тоже не знает).
MONO=/usr/share/fonts/TTF/JetBrainsMono-Regular.ttf
if ! command -v grub-mkfont >/dev/null || [[ ! -f $MONO ]]; then
  echo "Нет grub-mkfont или JetBrains Mono: pacman -S grub ttf-jetbrains-mono" >&2
  exit 1
fi
sed -i "s/'uefi.systemd-boot'/'uefi.grub'/" "$PROFILE/profiledef.sh"
rm -rf "$PROFILE/efiboot"
cp "$ROOT/iso/grub/grub.cfg" "$PROFILE/grub/grub.cfg"
cp -r "$ROOT/iso/grub/themes" "$PROFILE/grub/"

# Шрифты темы из Onest. Он переменный: -i выбирает начертание
# (0 — Regular, 327680 — Medium, 393216 — SemiBold), -n даёт имя,
# по которому их зовёт theme.txt («Sedmio Text Regular 22» и т. д.).
# Только латиница, кириллица, тире, кавычки и стрелки — файлы маленькие.
FONT="$ROOT/packages/sedmio-calamares/files/etc/calamares/branding/sedmio/fonts/Onest-Variable.ttf"
RANGE=0x20-0x7E,0xA0-0xFF,0x400-0x45F,0x2010-0x2027,0x2190-0x2193,0x2116-0x2116
mkfont() {  # имя, начертание, размер, файл
  grub-mkfont -n "$1" -i "$2" -s "$3" -r "$RANGE" \
    -o "$PROFILE/grub/themes/sedmio/$4.pf2" "$FONT" 2>/dev/null
}
mkfont "Sedmio Text"   0      16 text-16
mkfont "Sedmio Text"   0      18 text-18
mkfont "Sedmio Text"   0      22 text-22
mkfont "Sedmio Medium" 327680 22 medium-22
mkfont "Sedmio Bold"   393216 16 bold-16
mkfont "Sedmio Bold"   393216 56 bold-56
# Правка параметров (E) и командная строка — терминал, ему нужен
# моноширинный шрифт: с Onest буквы стояли вразрядку. Символы рамок
# (0x2500…) нужны дважды: рамка вокруг текста сплошная, а не из «- - |»,
# и высота строки GRUB берёт по самому высокому знаку — без них хвосты
# у «р», «у», «g» обрезались.
grub-mkfont -n "Sedmio Mono" -s 16 -r "$RANGE,0x2500-0x257F" \
  -o "$PROFILE/grub/themes/sedmio/mono-16.pf2" "$MONO" 2>/dev/null

# Сообщения самого GRUB (подсказки в правке параметров, ошибки) — по-русски
mkdir -p "$PROFILE/grub/locale"
cp /usr/share/locale/ru/LC_MESSAGES/grub.mo "$PROFILE/grub/locale/ru.mo"

sed -i 's/Arch Linux install medium/Sedmio Linux/' \
  "$PROFILE/grub/loopback.cfg" "$PROFILE/syslinux/"*.cfg
sed -i 's/^MENU TITLE Arch Linux/MENU TITLE Sedmio Linux/' "$PROFILE/syslinux/archiso_head.cfg"
cp "$ROOT/iso/syslinux/splash.png" "$PROFILE/syslinux/splash.png"

mkarchiso -v -w "$WORK/build" -o "$OUT" "$PROFILE"

echo
echo "Готово: $OUT"
