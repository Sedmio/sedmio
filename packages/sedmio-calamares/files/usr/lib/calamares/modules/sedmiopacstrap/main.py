# Calamares: установка пакетов Sedmio на диск с видимым ходом.
#
# pacstrap.sh делает всю работу; здесь его вывод читается построчно:
# каждая строка уходит в журнал установщика (кнопка «Журнал»), а по
# строкам pacman считается ход — сколько мегабайт скачано и какой пакет
# ставится сейчас.
#
# Метки этапов скрипт печатает сам: «@@sedmio <этап>», а пока идёт
# pacstrap — «@@sedmio tick» раз в 2 секунды, чтобы счётчик скачанного
# обновлялся и без новых строк от pacman.

import os
import re
import subprocess

import libcalamares

SCRIPT = "/usr/lib/sedmio/installer/pacstrap.sh"
TIMEOUT = 3600  # секунд; при медленной сети шаг может занять до часа

# Доли полосы хода этого шага
P_MIRRORS, P_SYNC, P_DOWNLOAD, P_INSTALL, P_HOOKS, P_FINISH = (
    0.0, 0.03, 0.05, 0.65, 0.95, 0.98)

UNITS = {"B": 1 / 1048576, "KiB": 1 / 1024, "MiB": 1, "GiB": 1024}

status = "Готовимся к установке программ…"


def pretty_name():
    return "Скачиваем и ставим программы"


def pretty_status_message():
    return status


class Progress:
    def __init__(self, root):
        self.cache = os.path.join(root, "var/cache/pacman/pkg")
        self.total = 0           # пакетов в установке
        self.download_mb = 0.0   # «Total Download Size»
        self.installed = 0
        self.downloading = False
        self.fraction = 0.0
        self.tail = []           # последние строки — для сообщения об ошибке

    def set(self, text, fraction):
        global status
        status = text
        self.fraction = max(self.fraction, min(fraction, 1.0))
        libcalamares.job.setprogress(self.fraction)

    def cache_mb(self):
        try:
            with os.scandir(self.cache) as it:
                return sum(e.stat().st_size for e in it if e.is_file()) / 1048576
        except OSError:
            return 0.0

    def show_download(self):
        if self.download_mb > 0:
            done = min(self.cache_mb(), self.download_mb)
            self.set("Скачиваем программы: {:.0f} из {:.0f} МБ".format(done, self.download_mb),
                     P_DOWNLOAD + (P_INSTALL - P_DOWNLOAD) * done / self.download_mb)
        else:
            self.set("Скачиваем программы…", P_DOWNLOAD)

    def line(self, raw):
        line = raw.rstrip("\n").strip()
        if not line:
            return
        if line == "@@sedmio tick":
            # Не в журнал: только обновить счётчик, пока идёт скачивание
            if self.downloading and not self.installed:
                self.show_download()
            return
        libcalamares.utils.debug(line)
        self.tail = (self.tail + [line])[-15:]

        if line.startswith("@@sedmio "):
            stage = line.split(None, 1)[1]
            if stage == "mirrors":
                self.set("Подбираем самые быстрые зеркала — до двух минут…", P_MIRRORS)
            elif stage == "packages":
                self.set("Получаем списки программ…", P_SYNC)
            elif stage == "finish":
                self.set("Настраиваем обновления Sedmio…", P_FINISH)
            return

        m = re.match(r"Packages \((\d+)\)", line)
        if m:
            self.total = int(m.group(1))
            return
        m = re.match(r"Total Download Size:\s+([\d.,]+)\s+(\S+)", line)
        if m:
            self.download_mb = float(m.group(1).replace(",", ".")) * UNITS.get(m.group(2), 1)
            return

        if line.endswith("downloading..."):
            self.downloading = True
            self.show_download()
            return

        m = re.match(r"(?:installing|upgrading|reinstalling) (\S+)\.\.\.$", line)
        if m:
            self.installed += 1
            n = max(self.total, self.installed)
            self.set("Устанавливаем {} ({} из {})".format(m.group(1), self.installed, n),
                     P_INSTALL + (P_HOOKS - P_INSTALL) * self.installed / n)
            return

        if line.startswith(":: Running post-transaction hooks"):
            self.set("Завершаем установку программ…", P_HOOKS)


def run():
    root = libcalamares.globalstorage.value("rootMountPoint")
    if not root:
        return ("Не задан корень установки",
                "Установщик не смонтировал целевой диск.")

    progress = Progress(root)
    try:
        code = libcalamares.utils.host_env_process_output(
            [SCRIPT, root], progress.line, "", TIMEOUT)
    except subprocess.CalledProcessError as e:
        code = e.returncode or 1
    if code:
        return ("Не удалось установить программы",
                "Чаще всего причина — сеть. Последние строки журнала:\n\n"
                + "\n".join(progress.tail))
    progress.set("Программы установлены", 1.0)
    return None
