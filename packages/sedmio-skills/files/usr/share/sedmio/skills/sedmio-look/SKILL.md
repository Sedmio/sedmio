---
name: sedmio-look
description: Внешний вид Sedmio — темы (цвета, шрифт, скругления, прозрачность), своя тема, акцентный цвет из обоев, обои, расположение и толщина панелей, закреплённые программы и порядок кнопок, цвета чужих программ и терминала. Читать, когда пользователь хочет поменять, как выглядит его Sedmio.
---

# Вид Sedmio

Две независимые оси: **тема** — как выглядит (цвета, шрифт, скругления),
**макет** — где стоят панели. Любая тема работает с любым макетом. Всё
меняется на ходу, без перезахода; проще всего — «Параметры» → «Тема» и
«Обои» (`sedmio-preferences theme`, `sedmio-preferences wallpaper`).
Системные темы в `/usr/share/sedmio/themes` не править — их перезапишет
обновление.

## Своя тема

1. Скопировать тему за основу:
   `mkdir -p ~/.local/share/sedmio/themes/<id> && cp
   /usr/share/sedmio/themes/sedmio/theme.json
   ~/.local/share/sedmio/themes/<id>/`. `<id>` — латиница, без `/` и `..`.
2. Поменять `name` (видно в «Параметрах»), `description` и значения.
3. Выбрать: `echo <id> > ~/.config/sedmio/theme` (или карточка в
   «Параметры» → «Тема»). Своя тема с id системной её перекрывает.

Ключи (разделы файла — только для порядка):

- `colors`: `paper` (фон окон), `paperDeep` (фон поглубже), `surface`
  (карточки, поля), `line`/`lineStrong` (линии), `ink`/`inkSoft`/
  `inkMuted` (текст: основной, второстепенный, бледный), `green` (акцент:
  кнопки, выбор), `greenWash` (фон выбранного), `greenSelect`,
  `textOnGreen` (текст на акценте), `leaf`, `terracotta` (опасное,
  ошибки), `terracottaSoft`, `success`, `warning`, `shadow`. Цвет —
  `#RRGGBB` или `#AARRGGBB`.
- `wallpaper`: `wallpaperTop`, `wallpaperMiddle`, `wallpaperBottom` —
  градиент обоев по умолчанию.
- `window`: `windowTitle`, `windowTitleInactive` (заголовок окна),
  `windowOutline` (контур), `titleHeight`, `windowRadius`.
- `fonts`: `fontFamily`, `fontSmall`, `fontBody`, `fontLarge`.
- `shapes`: `radius` (скругление карточек), `barWidth`, `border`,
  `frameRadius` (рамка вокруг экрана), `buttonSize`.
- `glass`: `glassOpacity` — 0…1, непрозрачность панелей и меню (под
  ними размытие). 1 — без прозрачности.
- `motion`: `animFast`, `animNormal` — длительность анимаций, мс.

Ошибка в файле не ломает систему: битый JSON, нет ключа или не тот тип —
берётся значение темы по умолчанию. Битая тема не показывается в
«Параметрах». Тёмной теме нужны тёмные `paper`/`surface` и светлые
`ink` — проверять, что текст читается и на `green` (`textOnGreen`).

## Акцент из обоев

`~/.config/sedmio/accent`: `wallpaper` — акцентные цвета (`green`,
`greenWash`, `greenSelect`, `textOnGreen`, `leaf`) поворачиваются к цвету
обоев, `theme` — как в теме. Цвета-смыслы (terracotta, success, warning)
не меняются.

## Обои

`~/.config/sedmio/wallpaper.json`: `{"image": "/полный/путь.jpg"}`; нет
файла или он битый — обои Sedmio. Лучше выбирать в «Параметры» → «Обои»: они ещё
обновляют картинку заставки и экрана блокировки
(`~/.local/state/sedmio/wallpaper`).

## Панели

`~/.config/sedmio/layout`, первая строка — макет:

- `left` — полоса слева в рамке вокруг экрана (по умолчанию);
- `dock` — сверху тонкая панель, снизу док по центру (прячется под
  развёрнутым окном);
- `taskbar` — сверху тонкая панель, снизу панель задач на всю ширину.

Следующие строки — толщина в пикселях: `left=48` (40…72), `top=40`
(32…56), `dock=52` (44…96), `taskbar=44` (36…64). Вне пределов — по
умолчанию.

Закреплённые программы — `~/.config/sedmio/panel.json`
(`{"pinned": ["sedmio-files", "firefox"]}`, имена .desktop без
расширения; закрепить — правым щелчком по кнопке или в Пуске, порядок —
перетаскиванием). Порядок кнопок состояния — `~/.config/sedmio/bar.json`
(`{"order": [...]}`, имена модулей; меняется перетаскиванием). Эти два
файла оболочка читает при запуске: после правки руками — `quickshell ipc
-p /usr/share/sedmio/shell call shell reload`.

## Чужие программы и терминал

- Программы Qt/KDE и GTK красятся по теме сами (служба
  `sedmio-theme-sync`: схема `Sedmio` в `~/.config/kdeglobals`,
  `~/.config/gtk-{3,4}.0/sedmio.css`). Выбранную пользователем другую
  схему цветов или шрифт служба не перетирает.
- Терминал Ghostty — `~/.config/ghostty/config.ghostty`, тема Sedmio
  подключена оттуда.
