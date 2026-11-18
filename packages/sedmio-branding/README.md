# sedmio-branding

Шрифт Onest для всей системы (оболочка, установщик). Дальше сюда пойдёт
всё, что отвечает за внешний вид:

- тема загрузчика;
- тема Plymouth (заставка при загрузке);
- тема SDDM (экран входа);
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
- Экран входа — тема Breeze из Plasma, как на рабочем столе
  (`packages/sedmio-settings/files/etc/sddm.conf.d/10-sedmio.conf`).
  Своя тема SDDM заменит её здесь.
- Ярлыки панели задач без отсутствующих программ —
  скрипт обновления Plasma в `packages/sedmio-settings`.
