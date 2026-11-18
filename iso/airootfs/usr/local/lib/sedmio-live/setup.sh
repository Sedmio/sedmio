#!/usr/bin/env bash
# Настройка live-системы. Выполняется при сборке образа внутри airootfs
# (pacman-хук zzzz90-sedmio-live.hook).
set -euo pipefail

locale-gen

# Пользователь live: без пароля, вход автоматический (greetd,
# /etc/greetd/sedmio-live.toml).
if ! id live &>/dev/null; then
  useradd -m -G wheel,video,audio,storage,network -s /bin/bash -c "Sedmio" live
  passwd -d live
fi

# Сеть — NetworkManager (как в установленной системе), а не iwd/networkd из releng.
systemctl disable iwd.service systemd-networkd.service systemd-networkd.socket \
  systemd-networkd-wait-online.service 2>/dev/null || true
systemctl enable NetworkManager.service greetd.service
systemctl set-default graphical.target

# Хук нужен только при сборке образа. releng удаляет лишь свои хуки,
# а наш иначе сработал бы при установке пакетов на диск.
rm -f /etc/pacman.d/hooks/zzzz90-sedmio-live.hook
