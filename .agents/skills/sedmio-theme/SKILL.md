---
name: sedmio-theme
description: Вид Sedmio — темы (theme.json, Sedmio.Style, Theme.*), акцент из обоев, цвета чужих программ, однотонные символы Lucide, рамки окон KWin и свои заголовки окон. Читать перед правкой цветов, шрифтов, значков, рамок или добавлением новой темы.
---

# Темы, символы, рамки окон

Пакет `packages/sedmio-theme`, решения — docs/decisions.md §14 и §20.

## Тема — это только значения

- Тема — `/usr/share/sedmio/themes/<тема>/theme.json` (свои —
  `~/.local/share/sedmio/themes`): цвета (`paper`, `surface`, `ink`,
  `inkSoft`, `green`, `greenWash`, `terracotta`…), обои (градиент),
  окно (`windowTitle`, `titleHeight`, `windowRadius`), шрифты, формы
  (`radius`, `buttonSize`), `glassOpacity`, движение (`animFast`,
  `animNormal`). Разделы файла только для порядка — в `Theme` ключи
  лежат рядом.
- Выбор — первая строка `~/.config/sedmio/theme`, по умолчанию
  `/etc/xdg/sedmio/theme`, иначе `sedmio`.
- Тема не приносит QML. Где стоят панели — макет оболочки, отдельная
  ось (навык `sedmio-shell`): любая тема с любым макетом.
- Тема по умолчанию вшита в модуль и рамки: битый файл, нет ключа, не
  тот тип — берётся вшитое. Вшивается `themes/sedmio/theme.json`: новый
  ключ — в него (и в остальные темы, если они есть).

## В коде

- QML: `import Sedmio.Style` → `Theme.paper`, `Theme.radius`,
  `Theme.animFast`. Своих цветов и копий палитры в программах не
  заводить — только `Theme.*`. Полупрозрачное — `Qt.alpha(Theme.ink, 0.4)`.
- Акцент из обоев перекрашивает `green`, `greenWash`, `greenSelect`,
  `textOnGreen`, `leaf`. Цвета-смыслы (`terracotta` — опасное, `success`,
  `warning`) не меняются: для «удалить» — terracotta, не green.
- Всё меняется на ходу: файлы темы и выбора отслеживаются. Значки темы
  KDE перекрашиваются по палитре, поэтому `SIcon` перезапрашивает картинку
  по `Theme.paletteSerial`.
- Чужие программы (Qt/KDE, GTK) получают цвета от службы
  `sedmio-theme-sync`: схема `Sedmio.colors` и `kdeglobals`. Она же
  находит акцент из обоев.

## Однотонные символы (Lucide)

Кнопки, меню и боковые панели — однотонные символы Lucide, значки
программ и файлов — цветные из темы значков.

- `symbols/names.json`: имя значка freedesktop → файл
  `symbols/lucide/<файл>.svg`. В QML — `SIcon { name: "edit-undo";
  symbolic: true }` (или `Symbols.url(имя, цвет, размер)`); имени нет в
  списке — рисуется обычный значок темы.
- Новый символ: взять SVG той же версии Lucide
  (`https://cdn.jsdelivr.net/npm/lucide-static@0.469.0/icons/<имя>.svg`),
  положить в `symbols/lucide/`, строку в `names.json`, pkgrel +1.
  Имя слева — freedesktop (`document-save`, `edit-redo`,
  `draw-freehand`…), чтобы без символа был осмысленный запасной значок.

## Рамки и заголовки окон

- Рамки — свой плагин KWin `org.sedmio.decoration` (`code/decoration`,
  KDecoration3), читает раздел `window` темы. Новый .so KWin подхватывает
  только после выхода из сеанса и входа — так и говорить пользователю.
  Значения из theme.json применяются на ходу.
- Главные окна наших программ рисуют заголовок сами: боковая панель и
  полоса инструментов до верха окна, кнопки — `WindowControls`,
  перетаскивание — `WindowDragArea` (оба из Sedmio.Style). Чтобы рамка
  не рисовала свою полосу заголовка, app_id программы
  (`QGuiApplication::setDesktopFileName`) — в списке
  `code/common/ownheader.h`. Диалоги и окна постоянного размера — с
  обычным заголовком рамки, в список не добавлять.
