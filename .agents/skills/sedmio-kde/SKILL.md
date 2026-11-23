---
name: sedmio-kde
description: Двигатель под Sedmio — KWin и его скрипты на QML, глобальные клавиши (kglobalaccel), kconf_update, настройки KDE по умолчанию, порталы xdg-desktop-portal, сеанс и службы systemd пользователя. Читать перед правкой скриптов KWin, клавиш, служб сеанса, kconf-скриптов и всего, что трогает KDE-часть системы.
---

# KWin, KDE, сеанс

От Plasma осталась основа: KWin (окна, плавающие как в Windows), Qt/KF,
kded, powerdevil, порталы. Всё видимое — своё. Решения — docs/decisions.md
§12, §13, §15.

## Настройки по умолчанию

- Сначала — значение по умолчанию в `/etc/xdg/<файл>rc` (пакет
  sedmio-settings): пользователь может его поменять, и его выбор главнее.
  Свой `~/.config` на машине разработчика перекрывает `/etc/xdg` —
  проверять в ВМ на чистом пользователе.
- Если значение нужно записать пользователю (Plasma кладёт своё в
  `~/.config/kdedefaults`, KWin читает только `~/.config`…) —
  kconf_update: `/usr/share/kconf_update/<имя>.upd` + скрипт. Трогать
  только то, что пользователь не менял (пустое или по умолчанию),
  выбранное им не перезаписывать.
- Найти ключ: поменять настройку мышью и посмотреть, что изменилось в
  `~/.config` (`ls -lt ~/.config | head`).

## Скрипты KWin (QML)

Пример — `sedmio-snap` (sedmio-shell, `/usr/share/kwin/scripts`),
`sedmio-windowkeys` (sedmio-settings). Модулю оболочки скрипт
привязывается полем `kwinScripts` (навык `sedmio-shell`).

- KWin кэширует QML по Id: перезалил под тем же Id — грузится старый.
  Отлаживать под новым Id, включать `kwriteconfig6 --file kwinrc --group
  Plugins --key <id>Enabled true` + `qdbus6 org.kde.KWin /KWin reconfigure`.
- `signal.connect()` из JS на окна переживает выгрузку скрипта и сыплет
  ошибками. Подписываться декларативно: `Instantiator { model:
  KWin.WindowModel {} delegate: Connections { … } }`.
- `Workspace.windowList()` в декларативной обёртке нет —
  `KWin.Workspace.stackingOrder`.
- `Window`, показанное привязкой `visible`, KWin не выводит — только
  `show()`/`hide()`, x/y задавать после `show()`.
- Клавиши (Esc, стрелки) получает только окно с `flags: Qt.Popup`.
- `Workspace.cursorPos` в `interactiveMoveResizeStepped` отстаёт на шаг —
  читать через `Qt.callLater`.
- `print()` скрипта — в `journalctl --user`. Слои оболочки скрипт видит
  как `normalWindow`: фильтровать окна по `resourceClass`.

## Глобальные клавиши

- Клавиша программы — `.desktop` в `/usr/share/kglobalaccel/` с
  `X-KDE-Shortcuts` (без `NoDisplay=true`: такие kglobalaccel при входе
  отключает). Проверять перезаходом, не только заливкой на ходу.
- Клавиши, которые по умолчанию у KDE/Spectacle, забирает kconf-скрипт —
  только если они не менялись. kglobalaccel отдаёт клавиши действия не
  в том порядке, в каком назначали: сравнивать без учёта порядка.
- Клавиши раскладки и переключение языка без просьбы пользователя не
  менять.

## Сеанс и службы

- Сеанс — `sedmio-session.target` (пакет sedmio-session):
  `sedmio-kwin.service` (KWin), затем заставка, оболочка
  (`sedmio-shell.service`), окна паролей, session-manager. Переменные
  сеанса — `/usr/lib/environment.d/*.conf` в пакетах.
- `BusName=` без `Type=` делает службу `Type=dbus`; два юнита с одним
  BusName systemd ломает. Готовность KWin ждём `ExecStartPost=gdbus wait
  --session org.kde.KWinWrapper`.
- `Type=oneshot`, который запускает программу через
  `/usr/lib/sedmio/launch` и сразу выходит, — systemd убьёт программу
  вместе с группой службы. Ждать, пока программа сменит cgroup.
- Скрипты на `set -euo pipefail`: `x="$(getent … | cut …)"` при пустом
  ответе молча обрывает скрипт — `|| true`.
- Plasma-службы, которые ещё нужны, правятся drop-in'ами
  (`plasma-*.service.d/`), не копией юнита.

## Порталы

- Выбор файла и «Открыть с помощью» — наш портал (`sedmio-files
  --portal`), строки `FileChooser=sedmio;kde`, `AppChooser=sedmio;kde` в
  `/etc/xdg/xdg-desktop-portal/kde-portals.conf` (копия файла
  plasma-workspace — после его обновления сверять). Qt/KDE-программы
  идут в портал с `PLASMA_INTEGRATION_USE_PORTAL=1`, GTK3 — с
  `GTK_USE_PORTAL=1` (environment.d).
- Проверять портал клиентом, который ждёт сигнал `Response`: `gdbus
  call` выходит сразу, и портал отменяет запрос. Файлы — `OpenFile` с
  дескриптором; `OpenURI` с `file://` портал отклоняет.
