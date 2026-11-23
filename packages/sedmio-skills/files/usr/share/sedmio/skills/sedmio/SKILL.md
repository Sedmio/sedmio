---
name: sedmio
description: Как устроена Sedmio Linux на этом компьютере — что в ней своё, где лежат настройки пользователя, какие есть команды и клавиши, как обновлять и откатывать систему снимками, как смотреть журналы и чинить сбои (оболочка не запустилась, окно не открывается). Читать перед любой работой с системой пользователя Sedmio — настройкой, установкой, починкой.
---

# Sedmio Linux

Sedmio — дистрибутив на Arch Linux: окна, клавиатура и буфер обмена
ведут себя как в Windows, вид — свой. Окна ведёт KWin (плавающие окна),
всё видимое своё: оболочка (панель, Пуск, рамка, уведомления — на
Quickshell), «Параметры», «Файлы», «Программы», «Ножницы», диспетчер
задач, вход и блокировка, тема. Интерфейс только на русском.

## Правила

- **Не править файлы в `/usr` и не трогать `/etc` без нужды.** Их ставят
  пакеты, и следующее обновление молча вернёт как было. Всё, что можно
  настроить, настраивается в домашней папке (ниже) или через
  «Параметры»; системные значения по умолчанию из `/etc/xdg`
  перекрываются одноимённым файлом в `~/.config`.
- Перед рискованным для системы (удаление пакетов, правка `/etc`,
  загрузчик, драйверы) — снимок: `pkexec /usr/lib/sedmio/update-helper
  create "что делаю"`. Откатить можно из «Параметры» → «Обновление».
- Программы ставить через «Программы» (`sedmio-store`) или pacman;
  обновлять систему — «Параметры» → «Обновление» (или
  `sudo pacman -Syu`: снимок перед ним сделается сам).
- Делать то, о чём просят. Не менять раскладку, клавиши, тему и модули
  «заодно». Перед изменением файла настроек — показать, что поменяется.
- Пользователю отвечать по-русски.

## Где настройки пользователя

| Файл | Что |
|---|---|
| `~/.config/sedmio/theme` | выбранная тема (первая строка — её id) |
| `~/.config/sedmio/accent` | `wallpaper` — акцент из обоев, `theme` — из темы |
| `~/.config/sedmio/layout` | расположение панелей и их размеры |
| `~/.config/sedmio/wallpaper.json` | обои `{"image": "/путь"}` |
| `~/.config/sedmio/modules` | включённые/выключенные модули (`имя=on|off`) |
| `~/.config/sedmio/panel.json` | закреплённые программы на панели |
| `~/.config/sedmio/bar.json` | порядок кнопок состояния на панели |
| `~/.local/share/sedmio/themes/<id>/` | свои темы |
| `~/.local/share/quickshell/clipboard` | история буфера обмена |
| `~/Applications` | программы AppImage, добавленные через «Программы» |

Вид, темы, панели — навык `sedmio-look`. Модули — навык `sedmio-modules`.
Остальное (мышь, клавиатура, звук, сеть, питание, экраны, программы по
умолчанию, автозапуск) — «Параметры»: `sedmio-preferences <раздел>`,
разделы `display theme wallpaper modules mouse keyboard sound network
bluetooth power defaults autostart account datetime updates about`. Там
же — стандартные файлы KDE (`kxkbrc`, `kcminputrc`, `powerdevilrc`…).

## Клавиши

Win — Пуск. Win+V — буфер обмена. Win+N — уведомления. Win+X — быстрые
ссылки. Win+E — «Файлы». Win+I — «Параметры». Win+L — блокировка.
Win+1…9 — окна с панели. PrtSc и Win+Shift+S — «Ножницы» (область),
Win+PrtSc — весь экран, Alt+PrtSc — окно. Ctrl+Shift+Esc — диспетчер
задач. Ctrl+Alt+Del — выход/выключение. Alt+Tab — переключение окон,
Win+Tab — обзор. Win+↑/↓ — развернуть/свернуть, Win+M — свернуть все,
Win+Ctrl+D — новый рабочий стол. Раскладка us/ru — Alt+Shift (и
Win+Пробел). Менять клавиши — «Параметры» → «Клавиатура».

## Команды

- `sedmio-preferences [раздел]`, `sedmio-store [id программы]`,
  `sedmio-files [путь]`, `sedmio-tasks`, `sedmio-screenshot-editor <файл>`.
- `sedmio-modules` — модули (навык `sedmio-modules`).
- `quickshell ipc -p /usr/share/sedmio/shell call <цель> <функция>` —
  команды оболочке: `launcher toggle`, `control openSection network`,
  `layout reload`, `shell reload`…
- Снимки системы: `/usr/lib/sedmio/update-snapshots` (список),
  `pkexec /usr/lib/sedmio/update-helper create|delete|restore <id>`.

## Обновления и снимки

Перед каждой работой pacman система сама делает снимок btrfs (копия `@`,
хранятся 5 последних автоматических, ручные — пока не удалят). Возврат —
«Параметры» → «Обновление» → снимок → вернуть; действует после
перезагрузки, текущее состояние само становится снимком. Загрузились в
снимок и всё хорошо — там же «Оставить эту версию». Если система не
загружается — в меню загрузки пункт предыдущей версии. Ход обновления —
`/run/sedmio-update/upgrade.log`.

## Сбои и журналы

- Журнал части сеанса: `journalctl --user -u <служба> -b`. Службы:
  `sedmio-kwin` (окна), `sedmio-shell` (панель, Пуск), `sedmio-agents`
  (окна паролей), `sedmio-session-manager` (выход, выключение),
  `sedmio-theme-sync` (цвета программ), `sedmio-splash` (заставка).
- Оболочка упала трижды за минуту — сверху плашка «Оболочка Sedmio не
  запустилась» с кнопкой «Перезапустить». Без панели работают Alt+Tab,
  Ctrl+Shift+Esc («Запустить новую задачу») и Ctrl+Alt+Del. Причина —
  в `journalctl --user -u sedmio-shell -b`.
- Перечитать оболочку без перезапуска — `quickshell ipc -p
  /usr/share/sedmio/shell call shell reload`; перезапустить —
  `systemctl --user restart sedmio-shell`.
- Окна паролей не появляются — `systemctl --user status sedmio-agents`.
  После трёх падений работают запасные окна KDE; вернуть свои:
  `systemctl --user reset-failed sedmio-agents && systemctl --user start
  sedmio-agents`.
- Свои окна выбора файлов не нравятся или сломались — окна KDE одному
  пользователю: скопировать `/etc/xdg/xdg-desktop-portal/kde-portals.conf`
  в `~/.config/xdg-desktop-portal/` без строк `FileChooser=` и
  `AppChooser=`.
- Мало места или памяти — система предупреждает сама (уведомления).
  Что ест память — диспетчер задач (Ctrl+Shift+Esc).
