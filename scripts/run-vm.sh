#!/usr/bin/env bash
# Запускает собранный ISO в виртуалке QEMU/KVM (UEFI), чтобы проверить
# live-сессию и установку. Работает и в WSL2 (окно показывает WSLg).
#
#   scripts/run-vm.sh            # загрузка с ISO, диск out/vm/disk.qcow2
#   scripts/run-vm.sh --disk     # загрузка с диска (после установки)
#   scripts/run-vm.sh --reset    # удалить диск и NVRAM, начать с чистого
#
# Нужны: qemu-desktop edk2-ovmf (pacman -S qemu-desktop edk2-ovmf)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VM="$ROOT/out/vm"
DISK="$VM/disk.qcow2"
VARS="$VM/OVMF_VARS.4m.fd"
OVMF=/usr/share/edk2/x64

mode=iso
case "${1:-}" in
  --disk)  mode=disk ;;
  --reset) rm -rf "$VM"; echo "Виртуалка сброшена."; exit 0 ;;
  "")      ;;
  *)       echo "Неизвестный параметр: $1" >&2; exit 1 ;;
esac

ISO="$(ls -t "$ROOT"/out/iso/sedmio-*.iso 2>/dev/null | head -1 || true)"
if [[ $mode == iso && -z $ISO ]]; then
  echo "Нет ISO в out/iso. Сначала: sudo scripts/build-iso.sh" >&2
  exit 1
fi

mkdir -p "$VM"
[[ -f $DISK ]] || qemu-img create -f qcow2 "$DISK" 60G >/dev/null
[[ -f $VARS ]] || cp "$OVMF/OVMF_VARS.4m.fd" "$VARS"

args=(
  -enable-kvm
  # -cpu host: виртуальный процессор как настоящий (Zen 4, AVX-512) —
  # пакеты CachyOS znver4 на другом не запустятся
  -cpu host -smp 6 -m 8G
  -machine q35
  -drive if=pflash,format=raw,readonly=on,file="$OVMF/OVMF_CODE.4m.fd"
  -drive if=pflash,format=raw,file="$VARS"
  -drive file="$DISK",if=virtio,format=qcow2
  # Стандартная VGA: разрешение задаётся здесь, окно его не переопределяет
  -device VGA,edid=on,xres=1600,yres=900 -display gtk,zoom-to-fit=on
  -device virtio-net-pci,netdev=net0 -netdev user,id=net0
  -device qemu-xhci -device usb-tablet
  -audiodev none,id=snd0
  # Управление и снимки экрана:
  #   echo 'screendump shot.png -f png' | socat - UNIX-CONNECT:out/vm/monitor.sock
  -monitor unix:"$VM/monitor.sock",server,nowait
  # Гостевой агент: команды внутри виртуалки — scripts/vm-exec.sh
  -chardev socket,path="$VM/qga.sock",server=on,wait=off,id=qga0
  -device virtio-serial -device virtserialport,chardev=qga0,name=org.qemu.guest_agent.0
  # Последовательный порт в файл: что гость пишет в /dev/ttyS0 (отладка
  # зависаний загрузки и выключения, когда экран и агент уже недоступны)
  -serial file:"$VM/serial.log"
)
if [[ $mode == iso ]]; then
  echo "Загрузка с $ISO"
  # bootindex, а не -boot order=d: OVMF берёт порядок из своей NVRAM,
  # и после установки первым там стоит диск.
  args+=(-drive file="$ISO",media=cdrom,if=none,id=cd0,readonly=on
         -device ide-cd,drive=cd0,bootindex=0)
fi

exec qemu-system-x86_64 "${args[@]}"
