#!/usr/bin/env bash
# Быстрая проверка темы меню загрузки без сборки ISO: маленький EFI-образ
# с iso/grub/grub.cfg и темой, запуск в QEMU и снимок экрана.
#
#   sudo bash tools/boot-theme/preview-grub.sh [снимок] [клавиши] [разрешение]
#   sudo bash tools/boot-theme/preview-grub.sh menu
#   sudo bash tools/boot-theme/preview-grub.sh edit "e" 1600x900       # правка по E
#   sudo bash tools/boot-theme/preview-grub.sh console "e ctrl-c"      # командная строка
#
# Клавиши — имена для sendkey монитора QEMU через пробел.
# Снимок: out/boot-theme/<снимок>.png. Пунктов «Проверить память» в этом
# образе нет: файла memtest в нём нет, и grub.cfg прячет пункт.
# Нужны: grub, ttf-jetbrains-mono, libisoburn, mtools, qemu-desktop,
# edk2-ovmf, socat.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
shot="${1:-menu}"; keys="${2:-}"; res="${3:-1920x1080}"
OUT="$ROOT/out/boot-theme"
T="$(mktemp -d)"
trap 'kill "${qemu:-}" 2>/dev/null || true; rm -rf "$T"' EXIT
G="$T/iso/boot/grub"
mkdir -p "$G/fonts" "$G/locale" "$OUT"

# Тема и grub.cfg — как в scripts/build-iso.sh, плейсхолдеры archiso — заглушки
cp -r "$ROOT/iso/grub/themes" "$G/"
sed -e 's/%INSTALL_DIR%/arch/g; s/%ARCH%/x86_64/g; s/%ARCHISO_UUID%/x/g; s/%KERNEL_PARAMS%//g' \
    -e "s/set gfxmode=.*/set gfxmode=\"$res,auto\"/" \
    "$ROOT/iso/grub/grub.cfg" | tr -d '\r' > "$G/grub.cfg"
tr -d '\r' < "$ROOT/iso/grub/themes/sedmio/theme.txt" > "$G/themes/sedmio/theme.txt"

FONT="$ROOT/packages/sedmio-calamares/files/etc/calamares/branding/sedmio/fonts/Onest-Variable.ttf"
MONO=/usr/share/fonts/TTF/JetBrainsMono-Regular.ttf
RANGE=0x20-0x7E,0xA0-0xFF,0x400-0x45F,0x2010-0x2027,0x2190-0x2193,0x2116-0x2116
mkfont() { grub-mkfont -n "$1" -i "$2" -s "$3" -r "$RANGE" -o "$G/themes/sedmio/$4.pf2" "$FONT" 2>/dev/null; }
mkfont "Sedmio Text"   0      16 text-16
mkfont "Sedmio Text"   0      18 text-18
mkfont "Sedmio Text"   0      22 text-22
mkfont "Sedmio Medium" 327680 22 medium-22
mkfont "Sedmio Bold"   393216 16 bold-16
mkfont "Sedmio Bold"   393216 56 bold-56
grub-mkfont -n "Sedmio Mono" -s 16 -r "$RANGE,0x2500-0x257F" \
  -o "$G/themes/sedmio/mono-16.pf2" "$MONO" 2>/dev/null
cp /usr/share/grub/unicode.pf2 "$G/fonts/"
cp /usr/share/locale/ru/LC_MESSAGES/grub.mo "$G/locale/ru.mo"

grub-mkrescue -o "$T/preview.iso" "$T/iso" >/dev/null 2>&1

cp /usr/share/edk2/x64/OVMF_VARS.4m.fd "$T/vars.fd"
qemu-system-x86_64 -enable-kvm -m 1G -machine q35 \
  -drive if=pflash,format=raw,readonly=on,file=/usr/share/edk2/x64/OVMF_CODE.4m.fd \
  -drive if=pflash,format=raw,file="$T/vars.fd" \
  -device VGA,edid=on,xres="${res%x*}",yres="${res#*x}" -display none \
  -cdrom "$T/preview.iso" -monitor unix:"$T/mon.sock",server,nowait &
qemu=$!

monitor() { echo "$1" | socat - UNIX-CONNECT:"$T/mon.sock" >/dev/null; }
sleep 7                                   # UEFI + GRUB + тема
for k in $keys; do monitor "sendkey $k"; sleep 0.4; done
sleep 1
monitor "screendump $T/shot.png -f png"
sleep 1
cp "$T/shot.png" "$OUT/$shot.png"
echo "Снимок: out/boot-theme/$shot.png"
