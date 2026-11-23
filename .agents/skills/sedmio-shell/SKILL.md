---
name: sedmio-shell
description: Оболочка Sedmio на Quickshell (панель, рамка, обои, меню, центр управления) и её модули — как устроена, как добавить или поменять модуль, как перечитать оболочку, наша сборка Quickshell и её патчи. Читать перед любой правкой в packages/sedmio-shell или packages/quickshell.
---

# Оболочка и модули

Оболочка — QML на Quickshell в `/usr/share/sedmio/shell`
(`packages/sedmio-shell/files/usr/share/sedmio/shell`), служба
`sedmio-shell.service` в сеансе Sedmio. Окна паролей (polkit, Wi‑Fi,
Bluetooth) — отдельный процесс `/usr/share/sedmio/agents`
(`sedmio-agents.service`): упадёт панель — запрос пароля не пропадёт.

## Устройство

- `shell.qml` — корень: на каждом экране обои, рамка, зоны (Exclusions),
  части `screen` модулей; один раз — части `main`.
- Синглтоны ядра: `ShellState` (что открыто, на каком экране; сигналы
  между модулями), `DesktopLayout` (макет left | dock | taskbar и размеры
  панелей из `~/.config/sedmio/layout`), `Modules` (какие модули
  включены), `JobsState` (ход копирования файлов).
- Общие элементы: `SText`, `SIcon`, `SButton`, `SSwitch`, `SSlider`,
  `BarButton`, `QuickTile`, `PopIn`, `Tooltip`. Цвета и размеры только из
  `Sedmio.Style` (`Theme.*`, навык `sedmio-theme`) — своих цветов в QML
  не заводить.
- Где стоят панели — макет (`DesktopLayout`), а не тема. Новое
  расположение — новый макет, у оболочки один QML на все темы.

## Модули

Всё, что можно выключить, — модуль: папка
`modules/<имя>/` с `module.json`. **Формат, части и что каждая получает —
в `modules/README.md`, читай его.** Коротко:

- Части: `status`, `screen`, `main`, `panel`, `center`, `popups`, `tile`,
  `osd`, `menu`, плюс `kwinScripts`. Грузит их `ModulePart` (Loader):
  часть с ошибкой не грузится, оболочка живёт.
- Включает и выключает только `sedmio-modules` (on/off/reset/list
  --json); «Параметры» → «Модули» зовут её же. Выбор —
  `~/.config/sedmio/modules`.
- Модули не знают друг о друге: не ссылаться на синглтоны другого
  модуля. Связь — сигналами `ShellState` (пример: кнопка громкости шлёт
  `ShellState.osdRequested(…)`, слушает модуль `osd`, если включён).
  Состояние, общее для частей модуля, — синглтон в его папке
  (`screenshot/ScreenshotState.qml`).
- Движок, который Quickshell не умеет остановить (сервер уведомлений,
  история буфера обмена), — `restartOnDisable: true`.
- Новые части оболочки делать модулями, если их можно выключить.

## Перечитать и проверить

Оболочка за файлами не следит (`settings.watchFiles: false`): pacman
меняет файлы по одному. Перечитывает хук pacman, вручную —
`/usr/lib/sedmio/shell-reload` (от root, все сеансы) или
`quickshell ipc -p /usr/share/sedmio/shell call shell reload` (от
пользователя). Не перечитал — работает старый код.

Ошибки QML — в журнале: `journalctl --user -u sedmio-shell -b`
(в ВМ — `journalctl -b | grep quickshell`). `console.log` туда не
попадает, для отладки — `console.warn`. После проверки журнал должен
быть чистым от твоих предупреждений.

## Ловушки QML и Quickshell

- Делегат Repeater/Variants уничтожается, как только его модель
  изменилась, — даже посреди обработчика. После вызова, который меняет
  модель (`action.invoke()` закрывает уведомление), к `id` снаружи
  делегата уже не обратиться и функции компонента не вызвать: всё нужное
  взять в локальные переменные до вызова.
- Уведомление после действия может быть уже закрыто сервером —
  `dismiss()` только если `notification.tracked`.
- Qt 6.12: у Item есть FINAL-свойства `left`/`top` — своё свойство так
  не называть («Cannot override FINAL property»).
- `property x: x` и `base: base` — привязка на себя; id и свойство с
  одинаковым именем путаются.
- Процесс, запущенный оболочкой, — через `/usr/lib/sedmio/launch` (своя
  группа systemd), иначе он умрёт вместе с оболочкой.

## Наш Quickshell

`packages/quickshell` — Quickshell 0.3.2 с патчами (`*.patch`): список
окон под KWin, службы Plasma (OSD, раскладки), история буфера обмена,
ход копирования, миниатюры окон, меню трея, просмотр всех папок
конфигурации (`scan-subdirs` — без него модули не видят соседей), код
выхода `ipc call`. Патч делается из рабочей копии исходников:
`git diff` нужных путей → `<имя>.patch`, строка в `source` и
`prepare()`. Обновился Quickshell — оболочка перезапускается, а не
перечитывается (у старого процесса нет новых возможностей); в depends
sedmio-shell — минимальная версия (`quickshell>=…`).
