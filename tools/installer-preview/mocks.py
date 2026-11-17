"""Заглушки Calamares для предпросмотра QML-страниц без самого Calamares.

Повторяют только то, что используют наши страницы: свойства и методы
config каждого модуля, ViewManager и модели. Данные — примерные.
"""

import re

from PySide6.QtCore import (
    Property,
    QAbstractListModel,
    QModelIndex,
    QObject,
    Qt,
    Signal,
    Slot,
)


def stored(name, type_, notify):
    """Свойство только для чтения, которое берётся из self._v[name]."""
    return Property(type_, lambda self: self._v[name], notify=notify)


class ListModel(QAbstractListModel):
    """Простая модель из списка словарей; роли — ключи словарей."""

    def __init__(self, rows, roles, parent=None):
        super().__init__(parent)
        self._rows = list(rows)
        self._roles = {Qt.UserRole + i: r.encode() for i, r in enumerate(roles)}
        self._by_name = {v.decode(): k for k, v in self._roles.items()}

    def rowCount(self, parent=QModelIndex()):
        return 0 if parent.isValid() else len(self._rows)

    def data(self, index, role=Qt.DisplayRole):
        if not index.isValid():
            return None
        row = self._rows[index.row()]
        if role == Qt.DisplayRole:
            return next(iter(row.values()))
        name = self._roles.get(role)
        return row.get(name.decode()) if name else None

    def roleNames(self):
        return self._roles

    def set_rows(self, rows):
        self.beginResetModel()
        self._rows = list(rows)
        self.endResetModel()


# --------------------------------------------------------------- welcome

class RequirementsModel(ListModel):
    def __init__(self, fail_storage=False):
        rows = [
            dict(name="storage", satisfied=not fail_storage, mandatory=True, hasDetails=False,
                 details="На диске есть не меньше 30 ГиБ свободного места.",
                 negatedText="На диске меньше 30 ГиБ свободного места."),
            dict(name="ram", satisfied=True, mandatory=True, hasDetails=False,
                 details="Оперативной памяти не меньше 4 ГиБ.",
                 negatedText="Оперативной памяти меньше 4 ГиБ."),
            dict(name="power", satisfied=False, mandatory=False, hasDetails=False,
                 details="Компьютер подключён к сети питания.",
                 negatedText="Компьютер не подключён к сети питания."),
            dict(name="internet", satisfied=True, mandatory=False, hasDetails=False,
                 details="Есть подключение к интернету.",
                 negatedText="Нет подключения к интернету."),
            dict(name="root", satisfied=True, mandatory=True, hasDetails=False,
                 details="Установщик запущен с правами администратора.",
                 negatedText="Установщик запущен без прав администратора."),
        ]
        super().__init__(rows, ["name", "details", "negatedText", "satisfied", "mandatory", "hasDetails"])
        self._mandatory_ok = all(r["satisfied"] for r in rows if r["mandatory"])
        self._all_ok = all(r["satisfied"] for r in rows)

    @Property(bool, constant=True)
    def satisfiedMandatory(self):
        return self._mandatory_ok

    @Property(bool, constant=True)
    def satisfiedRequirements(self):
        return self._all_ok

    @Property(str, constant=True)
    def progressMessage(self):
        return ""


class WelcomeConfig(QObject):
    def __init__(self, fail_storage=False):
        super().__init__()
        self._req = RequirementsModel(fail_storage)

    @Property(QObject, constant=True)
    def requirementsModel(self):
        return self._req


# ---------------------------------------------------------------- locale

REGIONS = [
    ("Africa", "Африка"),
    ("America", "Америка"),
    ("Asia", "Азия"),
    ("Australia", "Австралия"),
    ("Europe", "Европа"),
    ("Pacific", "Тихий океан"),
]

ZONES = {
    "Africa": [("Cairo", "Каир"), ("Casablanca", "Касабланка"), ("Nairobi", "Найроби")],
    "America": [("Los_Angeles", "Лос-Анджелес"), ("New_York", "Нью-Йорк"),
                ("Sao_Paulo", "Сан-Паулу"), ("Toronto", "Торонто")],
    "Asia": [("Almaty", "Алматы"), ("Bangkok", "Бангкок"), ("Dubai", "Дубай"),
             ("Tashkent", "Ташкент"), ("Tbilisi", "Тбилиси"), ("Tokyo", "Токио"),
             ("Yerevan", "Ереван")],
    "Australia": [("Melbourne", "Мельбурн"), ("Sydney", "Сидней")],
    "Europe": [("Belgrade", "Белград"), ("Berlin", "Берлин"), ("Helsinki", "Хельсинки"),
               ("Istanbul", "Стамбул"), ("Kyiv", "Киев"), ("London", "Лондон"),
               ("Madrid", "Мадрид"), ("Minsk", "Минск"), ("Moscow", "Москва"),
               ("Paris", "Париж"), ("Prague", "Прага"), ("Riga", "Рига"),
               ("Tallinn", "Таллин"), ("Vilnius", "Вильнюс"), ("Warsaw", "Варшава")],
    "Pacific": [("Auckland", "Окленд"), ("Honolulu", "Гонолулу")],
}


class ZonesModel(ListModel):
    regionChanged = Signal()

    def __init__(self):
        super().__init__([], ["name", "key"])
        self._region = ""

    def _get_region(self):
        return self._region

    def _set_region(self, region):
        if region != self._region:
            self._region = region
            self.set_rows(dict(name=n, key=k) for k, n in ZONES.get(region, []))
            self.regionChanged.emit()

    region = Property(str, _get_region, _set_region, notify=regionChanged)


class LocaleConfig(QObject):
    currentTimezoneCodeChanged = Signal()
    currentLanguageCodeChanged = Signal()
    currentLCCodeChanged = Signal()

    def __init__(self):
        super().__init__()
        self._regions = ListModel([dict(name=n, key=k) for k, n in REGIONS], ["name", "key"])
        self._zones = ZonesModel()
        self._tz = "Europe/Berlin"
        self._lang = "en_US.UTF-8 UTF-8"
        self._lc = "en_US.UTF-8 UTF-8"

    @Property(QObject, constant=True)
    def regionModel(self):
        return self._regions

    @Property(QObject, constant=True)
    def regionalZonesModel(self):
        return self._zones

    @Property("QStringList", constant=True)
    def supportedLocales(self):
        return ["en_US.UTF-8 UTF-8", "ru_RU.UTF-8 UTF-8"]

    @Property(str, notify=currentTimezoneCodeChanged)
    def currentTimezoneCode(self):
        return self._tz

    @Property(str, notify=currentTimezoneCodeChanged)
    def currentTimezoneName(self):
        region, _, zone = self._tz.partition("/")
        names = dict(ZONES.get(region, []))
        return names.get(zone, zone)

    def _get_lang(self):
        return self._lang

    def _set_lang(self, v):
        if v != self._lang:
            self._lang = v
            print("язык:", v)
            self.currentLanguageCodeChanged.emit()

    currentLanguageCode = Property(str, _get_lang, _set_lang, notify=currentLanguageCodeChanged)

    def _get_lc(self):
        return self._lc

    def _set_lc(self, v):
        if v != self._lc:
            self._lc = v
            self.currentLCCodeChanged.emit()

    currentLCCode = Property(str, _get_lc, _set_lc, notify=currentLCCodeChanged)

    @Slot(str, str)
    def setCurrentLocation(self, region, zone):
        self._tz = f"{region}/{zone}"
        self.currentTimezoneCodeChanged.emit()


# ----------------------------------------------------------------- users

TRANSLIT = dict(zip(
    "абвгдеёжзийклмнопрстуфхцчшщъыьэюя",
    ["a", "b", "v", "g", "d", "e", "e", "zh", "z", "i", "y", "k", "l", "m", "n", "o",
     "p", "r", "s", "t", "u", "f", "kh", "ts", "ch", "sh", "shch", "", "y", "", "e",
     "yu", "ya"],
))
LOGIN_RX = re.compile(r"^[a-z_][a-z0-9_-]*$")
HOST_RX = re.compile(r"^[a-zA-Z0-9][-a-zA-Z0-9_]*$")


def transliterate(text):
    return "".join(TRANSLIT.get(ch, ch) for ch in text.lower())


class UsersConfig(QObject):
    changed = Signal()

    def __init__(self):
        super().__init__()
        self._v = dict(fullName="", loginName="", hostname="", userPassword="",
                       userPasswordSecondary="", doAutoLogin=False)
        self._custom_login = False
        self._custom_host = False

    fullName = stored("fullName", str, changed)
    loginName = stored("loginName", str, changed)
    hostname = stored("hostname", str, changed)
    userPassword = stored("userPassword", str, changed)
    userPasswordSecondary = stored("userPasswordSecondary", str, changed)
    doAutoLogin = stored("doAutoLogin", bool, changed)

    @Property(str, notify=changed)
    def loginNameStatus(self):
        login = self._v["loginName"]
        if not login:
            return ""
        if len(login) > 31:
            return "Логин слишком длинный."
        if not LOGIN_RX.match(login):
            return "Логин может содержать только строчные латинские буквы, цифры, «_» и «-»."
        if login == "root":
            return "Логин «root» занят системой."
        return ""

    @Property(str, notify=changed)
    def hostnameStatus(self):
        host = self._v["hostname"]
        if host and not HOST_RX.match(host):
            return "В имени компьютера можно использовать только латинские буквы, цифры и «-»."
        return ""

    @Property(int, notify=changed)
    def userPasswordValidity(self):
        return 0 if self._v["userPassword"] else 2

    @Property(str, notify=changed)
    def userPasswordMessage(self):
        return "" if self._v["userPassword"] else "Пароль не может быть пустым."

    @Property(bool, notify=changed)
    def ready(self):
        v = self._v
        return bool(v["fullName"] and v["loginName"] and v["hostname"]
                    and not self.loginNameStatus and not self.hostnameStatus
                    and v["userPassword"] and v["userPassword"] == v["userPasswordSecondary"])

    def _set(self, name, value):
        if self._v[name] != value:
            self._v[name] = value
            self.changed.emit()

    @Slot(str)
    def setFullName(self, name):
        self._set("fullName", name)
        clean = re.sub(r"[^a-z0-9 ]", " ", transliterate(name)).split()
        if clean and not self._custom_login:
            self._set("loginName", clean[0] + "".join(p[0] for p in clean[1:]))
        if not self._custom_host:
            self._set("hostname", f"{self._v['loginName']}-pc" if self._v["loginName"] else "")

    @Slot(str)
    def setLoginName(self, login):
        self._custom_login = True
        self._set("loginName", login)

    @Slot(str)
    def setHostName(self, host):
        self._custom_host = True
        self._set("hostname", host)

    @Slot(str)
    def setUserPassword(self, p):
        self._set("userPassword", p)

    @Slot(str)
    def setUserPasswordSecondary(self, p):
        self._set("userPasswordSecondary", p)

    @Slot(bool)
    def setAutoLogin(self, b):
        self._set("doAutoLogin", b)


# --------------------------------------------------------------- summary

class SummaryConfig(QObject):
    def __init__(self, locale, users):
        super().__init__()
        self._locale = locale
        self._users = users
        self._model = ListModel([], ["title", "message"])

    def refresh(self):
        u = self._users
        self._model.set_rows([
            dict(title="Местоположение",
                 message=f"Часовой пояс: <b>{self._locale.currentTimezoneCode}</b>. "
                         "Язык и форматы: <b>русский</b>."),
            dict(title="Разметка диска",
                 message="Диск <b>Samsung SSD 980 PRO 1 ТБ (/dev/nvme0n1)</b> будет полностью очищен. "
                         "Будут созданы раздел EFI (1 ГиБ) и системный раздел btrfs (930 ГиБ)."),
            dict(title="Пользователь",
                 message=f"Имя <b>{u.fullName or '—'}</b>, логин <b>{u.loginName or '—'}</b>, "
                         f"компьютер <b>{u.hostname or '—'}</b>."),
        ])

    @Property(QObject, constant=True)
    def summaryModel(self):
        return self._model

    @Property(str, constant=True)
    def message(self):
        return "Обзор того, что произойдёт после начала установки."


# -------------------------------------------------------------- finished

class FinishedConfig(QObject):
    def __init__(self, failed=False):
        super().__init__()
        self._failed = failed

    @Property(bool, constant=True)
    def failed(self):
        return self._failed

    @Property(str, constant=True)
    def failureMessage(self):
        return "Не удалось установить загрузчик." if self._failed else ""

    @Property(str, constant=True)
    def failureDetails(self):
        return ("Command 'bootctl install' returned non-zero exit status 1.\n"
                "Failed to open '/boot/efi': No such file or directory") if self._failed else ""

    @Slot(bool)
    def doRestart(self, restart):
        print("перезагрузка:", restart)


# ----------------------------------------------------------- viewmanager

class ViewManager(QAbstractListModel):
    """Шаги установки и навигация, как у Calamares."""

    changed = Signal()

    def __init__(self, steps, exec_index, ready_check, on_step, on_quit):
        super().__init__()
        self._steps = steps
        self._exec = exec_index
        self._ready = ready_check
        self._on_step = on_step
        self._on_quit = on_quit
        self._index = 0
        self._progress = 0.0

    def rowCount(self, parent=QModelIndex()):
        return 0 if parent.isValid() else len(self._steps)

    def data(self, index, role=Qt.DisplayRole):
        if index.isValid() and role == Qt.DisplayRole:
            return self._steps[index.row()]
        return None

    def roleNames(self):
        return {Qt.DisplayRole: b"display"}

    @Property(int, notify=changed)
    def currentStepIndex(self):
        return self._index

    @Property(bool, notify=changed)
    def nextEnabled(self):
        return self._ready(self._index)

    @Property(str, notify=changed)
    def nextLabel(self):
        return "&Установить" if self._index == self._exec - 1 else "&Далее"

    @Property(bool, notify=changed)
    def backEnabled(self):
        return 0 < self._index < self._exec

    @Property(str, constant=True)
    def backLabel(self):
        return "&Назад"

    @Property(bool, notify=changed)
    def backAndNextVisible(self):
        return self._index < self._exec

    @Property(str, notify=changed)
    def quitLabel(self):
        return "&Готово" if self._index > self._exec else "&Отмена"

    @Property(bool, notify=changed)
    def quitEnabled(self):
        return self._index != self._exec

    @Property(bool, notify=changed)
    def quitVisible(self):
        return self._index < self._exec

    # Только для предпросмотра: ход установки на шаге exec
    @Property(float, notify=changed)
    def execProgress(self):
        return self._progress

    @Property(int, constant=True)
    def execIndex(self):
        return self._exec

    def refresh(self):
        self.changed.emit()

    def go(self, index):
        index = max(0, min(index, len(self._steps) - 1))
        if index != self._index:
            self._index = index
            self.changed.emit()
            self._on_step(index)

    def set_progress(self, value):
        self._progress = value
        self.changed.emit()

    @Slot()
    def next(self):
        if self.nextEnabled:
            self.go(self._index + 1)

    @Slot()
    def back(self):
        if self.backEnabled:
            self.go(self._index - 1)

    @Slot()
    def quit(self):
        self._on_quit()


class Stub(QObject):
    """Branding / Global / Network: наши страницы их почти не трогают."""

    @Property(bool, constant=True)
    def hasInternet(self):
        return True


class BrandingStub(Stub):
    pass


class GlobalStub(Stub):
    pass


class NetworkStub(Stub):
    pass
