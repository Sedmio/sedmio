# Профиль ISO

Здесь не лежит полный профиль archiso: только наши дополнения к стандартному
профилю `releng`. `scripts/build-iso.sh` при каждой сборке берёт свежий
`releng` из пакета `archiso` и накладывает поверх:

- `packages.x86_64` — пакеты, которые добавляются в live-образ;
- `airootfs/` — файлы, которые кладутся в корень live-системы;
- название образа `sedmio`;
- репозитории машины сборки (`/etc/pacman.conf`: CachyOS + multilib)
  плюс локальный репозиторий `[sedmio]` из `out/repo` (первым, выше всех);
- правила `NoExtract` из `sedmio-settings`.

Так обновления archiso подтягиваются сами, и не надо держать копию профиля.

## Live-сессия

- Автовход в Plasma (Wayland) под пользователем `live` без пароля,
  Calamares запускается сам (`/etc/xdg/autostart`), есть и в меню.
- Пользователя, локаль и службы настраивает `usr/local/lib/sedmio-live/setup.sh`
  при сборке образа (pacman-хук `zzzz90-sedmio-live.hook`).
- Сеть — NetworkManager вместо `iwd` и `systemd-networkd` из releng.
- Репозиторий `[sedmio]` лежит на образе в `/opt/sedmio/repo`: из него
  установщик ставит пакеты Sedmio на диск. В установленную систему
  прописывается уже сетевой `[sedmio]` (см. docs/decisions.md, п. 11).
- Live-система грузится со стандартным ядром `linux`. Установленная система
  получает `linux-cachyos` и `linux-lts` через пакеты `sedmio-host-*`.

## Меню загрузки

- UEFI: GRUB со своей темой вместо systemd-boot из releng (тот не умеет
  картинок и кириллицы). `grub/grub.cfg` — пункты меню, `grub/themes/sedmio/` —
  тема. Картинки рисует `tools/boot-theme/render.py` из компонентов
  установщика, шрифты (`*.pf2`: Onest для меню, JetBrains Mono для правки
  параметров по E) и русские сообщения GRUB добавляет `scripts/build-iso.sh`.
- BIOS: syslinux из releng, только название и заставка `syslinux/splash.png`.
- Быстро проверить тему без сборки образа:
  `sudo bash tools/boot-theme/preview-grub.sh menu` (маленький EFI-образ из
  `grub/grub.cfg` и темы, QEMU, снимок в `out/boot-theme/`).

## Сборка и проверка

```bash
scripts/build-packages.sh        # от обычного пользователя
sudo scripts/build-iso.sh
scripts/run-vm.sh                # QEMU/KVM, UEFI; работает и в WSL2
```
