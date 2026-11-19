#!/usr/bin/env bash
# Ставит систему Sedmio на диск, смонтированный Calamares:
#   pacstrap.sh <корень целевой системы>
#
# Пакеты берутся из репозиториев live-системы: CachyOS (znver4), Arch
# и [sedmio] — он лежит прямо на live-образе, в /opt/sedmio/repo.
#
# Запускает его модуль Calamares sedmiopacstrap: он читает вывод построчно
# и по нему показывает ход. Метки этапов для него — «@@sedmio <этап>».
set -euo pipefail
exec 2>&1

ROOT="${1:?не передан корень целевой системы}"
stage() { echo "@@sedmio $*"; }

# Профиль машины: есть батарея — ноутбук.
if compgen -G '/sys/class/power_supply/BAT*' > /dev/null; then
  host=sedmio-host-laptop
else
  host=sedmio-host-desktop
fi
echo "Профиль машины: $host"

# Ключи pacman в live-системе заполняет pacman-init.service при загрузке.
# Если pacman полезет в связку раньше, чем он закончит, ломаются оба
# (ключи CachyOS остаются недоверенными). start ждёт его окончания, а если
# он уже отработал — ничего не делает.
if systemctl cat pacman-init.service >/dev/null 2>&1; then
  systemctl start pacman-init.service
fi

# Зеркала Arch. reflector при загрузке live-системы берёт самые свежие
# зеркала, а не самые быстрые: на установке с такого скорость падала до
# 0,5 МБ/с, и шаг шёл почти полчаса. Меряем скорость сами; не вышло —
# остаётся список, выбранный при загрузке.
stage mirrors
fast=/tmp/sedmio-mirrorlist
if timeout 150 reflector --protocol https --age 12 --latest 25 --sort rate \
     --number 10 --download-timeout 4 --save "$fast" \
   && grep -q '^Server' "$fast"; then
  cp "$fast" /etc/pacman.d/mirrorlist
  echo "Зеркала Arch выбраны по скорости:"
  grep '^Server' /etc/pacman.d/mirrorlist
else
  echo "Не удалось замерить зеркала — оставляю выбранные при загрузке."
fi

stage packages
# Раз в 2 секунды — метка для установщика: по ней он обновляет счётчик
# скачанных мегабайт, даже пока долго качается один большой файл.
( while sleep 2; do stage tick; done ) &
ticker=$!
trap 'kill "$ticker" 2>/dev/null || true' EXIT
# -K: своё хранилище ключей в целевой системе; ключи Arch, CachyOS
#     и Sedmio добавляют в него пакеты *-keyring при установке.
# Без -c: пакеты скачиваются в кэш на целевом диске. Live-система живёт
# в оперативной памяти, и пара гигабайт пакетов туда не влезет.
# zlib-ng-compat указан явно: поставщика виртуальной зависимости pacman
# выбирает только среди явных целей. base тянет zlib из Arch, а CachyOS
# заменяет его своим, и первый же pacman -Syu спрашивал «Заменить zlib?».
# stdbuf: построчный вывод pacman, иначе он копится в буфере и ход
# установки не виден.
stdbuf -oL -eL pacstrap -K "$ROOT" \
  base linux-firmware sudo nano efibootmgr zlib-ng-compat \
  cachyos-keyring cachyos-mirrorlist cachyos-v4-mirrorlist \
  "$host"

kill "$ticker" 2>/dev/null || true
stage finish
# pacman.conf — как в live-системе, только [sedmio] берётся не с образа,
# а из сети: оттуда приходят обновления пакетов Sedmio (pacman -Syu).
# Подписи проверяются ключом из sedmio-keyring — его ставит sedmio-base.
# $arch подставляет сам pacman (x86_64), поэтому кавычки одинарные.
awk -v server='https://github.com/Sedmio/sedmio/releases/download/$arch' '
  /^\[sedmio\]/  { print; print "Server = " server; skip = 1; next }
  skip && /^$/   { skip = 0 }
  /^\[/          { skip = 0 }
  !skip
' /etc/pacman.conf > "$ROOT/etc/pacman.conf"

# Зеркала Arch — те же, что выбраны выше по скорости.
cp /etc/pacman.d/mirrorlist "$ROOT/etc/pacman.d/mirrorlist"

# База [sedmio], которую pacstrap взял с образа, — без подписи и новее
# сетевой по дате. pacman не стал бы скачивать сетевую базу, а подпись
# к ней взял бы, и первый pacman -Sy упал бы с «signature is invalid».
# Сразу качаем сетевую, иначе до первого pacman -Sy любая команда pacman
# предупреждает, что базы [sedmio] нет. Не вышло — не страшно, скачает
# первое обновление.
rm -f "$ROOT"/var/lib/pacman/sync/sedmio.*
arch-chroot "$ROOT" pacman -Sy >/dev/null \
  || echo "Базу [sedmio] скачать не удалось: её скачает первый pacman -Sy." >&2
