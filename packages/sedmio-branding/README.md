# sedmio-branding

Шрифт Onest для всей системы (оболочка, установщик) и заставка при
загрузке — тема Plymouth `sedmio` (`plymouth/`, картинки —
`tools/plymouth-theme/render.py`). Дальше сюда пойдёт
всё, что отвечает за внешний вид:

- тема загрузчика;
- обои, логотип, иконка меню «Пуск»;
- look-and-feel пакет Plasma (тема, цвета, раскладка панелей).

## Что уже сделано в других местах

- Меню загрузки live-образа (GRUB, тема Sedmio) — `iso/grub/`,
  исходники картинок — `tools/boot-theme/`.
- Установщик — `packages/sedmio-calamares` и `packages/calamares`.
- Меню загрузки установленной системы — systemd-boot, пункты
  «Sedmio Linux» и «Sedmio Linux (LTS kernel)»
  (`packages/sedmio-calamares/files/usr/lib/sedmio/installer/bootentries.sh`).
  Оформить его нельзя: текст рисует прошивка.
- Экраны входа и блокировки — `packages/sedmio-login` (greetd + Quickshell,
  kscreenlocker со своим видом).
- Ярлыки панели задач без отсутствующих программ —
  скрипт обновления Plasma в `packages/sedmio-settings`.
