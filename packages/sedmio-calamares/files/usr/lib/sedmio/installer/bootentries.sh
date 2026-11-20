#!/usr/bin/env bash
# Пункты меню systemd-boot для установленной системы. Запускается Calamares
# сразу после модуля bootloader:
#   bootentries.sh <корень целевой системы>
#
# Модуль bootloader ставит systemd-boot (bootctl) и делает пункты через
# kernel-install: копия ядра в /boot/<machine-id>/<версия>/. На Arch их
# никто не обновляет — pacman-хук mkinitcpio кладёт новое ядро в
# /boot/vmlinuz-<ядро>, а пункт так и смотрит на старую версию, модулей
# которой уже нет. После первого же обновления ядра система не загрузилась
# бы как следует.
#
# Поэтому пункты — по постоянным именам, которые mkinitcpio обновляет сам:
# /vmlinuz-linux-cachyos и /initramfs-linux-cachyos.img. Параметры ядра
# (root=UUID=…, подтом btrfs, шифрование) берём у модуля bootloader —
# он записал их в /etc/kernel/cmdline.
#
# Названия — латиницей: меню systemd-boot выводит текст средствами
# прошивки, а она кириллицу обычно не показывает.
set -euo pipefail

ROOT="${1:?не передан корень целевой системы}"
ESP="$ROOT/boot"

# Модуль bootloader дописывает параметры для каждого ядра, и в файле они
# повторяются («rw rootflags=… root=…» дважды) — оставляем по одному разу,
# порядок сохраняем.
cmdline="$(tr -s ' \n' '\n' < "$ROOT/etc/kernel/cmdline" | awk 'NF && !seen[$0]++' | paste -sd ' ')"
[[ -n $cmdline ]] || { echo "Пустой /etc/kernel/cmdline" >&2; exit 1; }
case " $cmdline " in *" rw "*) ;; *) cmdline="rw $cmdline" ;; esac
printf '%s\n' "$cmdline" > "$ROOT/etc/kernel/cmdline"

# Убираем пункты и копии ядер от kernel-install
machine_id="$(cat "$ROOT/etc/machine-id")"
rm -f "$ESP/loader/entries/$machine_id"-*.conf
rm -rf "${ESP:?}/$machine_id"

mkdir -p "$ESP/loader/entries"
written=0
for pkgbase_file in "$ROOT"/usr/lib/modules/*/pkgbase; do
  kernel="$(cat "$pkgbase_file")"
  [[ -f $ESP/vmlinuz-$kernel && -f $ESP/initramfs-$kernel.img ]] || {
    echo "Нет /boot/vmlinuz-$kernel или initramfs — пропускаю" >&2
    continue
  }
  case "$kernel" in
    linux-cachyos) entry=sedmio;     title="Sedmio Linux";            sort=1 ;;
    linux-cachyos-lts) entry=sedmio-lts; title="Sedmio Linux (LTS kernel)"; sort=2 ;;
    *)             entry="sedmio-$kernel"; title="Sedmio Linux ($kernel)"; sort=3 ;;
  esac
  cat > "$ESP/loader/entries/$entry.conf" <<EOF
title    $title
sort-key sedmio-$sort
linux    /vmlinuz-$kernel
initrd   /initramfs-$kernel.img
options  $cmdline
EOF
  echo "Пункт загрузки: $title ($entry.conf)"
  written=$((written + 1))
done
(( written > 0 )) || { echo "Не создано ни одного пункта загрузки" >&2; exit 1; }

# Меню: по умолчанию основное ядро, 3 секунды на выбор
default=sedmio.conf
[[ -f $ESP/loader/entries/$default ]] || default="$(basename "$(ls "$ESP"/loader/entries/sedmio*.conf | head -1)")"
cat > "$ESP/loader/loader.conf" <<EOF
default $default
timeout 3
console-mode keep
EOF
