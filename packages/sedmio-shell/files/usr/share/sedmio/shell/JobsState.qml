pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Kde

// Копирование файлов и другие долгие операции программ: сервер заданий
// (org.kde.kuiserver и org.kde.JobViewServer — раньше их держал
// plasmashell). Dolphin, Ark и всё, что работает с файлами через KIO,
// присылают сюда ход операции вместо своих окошек с прогрессом.
//
// Пока операция идёт, её карточка висит над уведомлениями; крестик её
// прячет, операция остаётся в центре уведомлений. Удачно законченная
// исчезает сама через несколько секунд, отменённая — сразу; неудачная
// всплывает и остаётся, пока её не закроют.
Singleton {
    id: root

    readonly property bool active: server.active

    // Все показанные, старые сверху.
    readonly property var jobs: server.jobs.values
    readonly property var running: jobs.filter(j => j.state !== "finished")

    // Спрятанные крестиком карточки (id операций).
    property var hidden: []
    readonly property var popups: jobs.filter(j => !hidden.includes(j.id))

    // Над какой карточкой мышь: её не убираем, пока читают.
    property int hovered: -1

    // Общий ход всех идущих операций, 0–100, для колокольчика.
    readonly property int percent: running.length === 0 ? 0
        : Math.round(running.reduce((sum, j) => sum + j.percent, 0) / running.length)

    function hide(job) {
        if (job.state === "finished") job.dismiss();
        else if (!hidden.includes(job.id)) hidden = hidden.concat([job.id]);
    }

    // Убрать все законченные — как «Очистить всё» в центре уведомлений.
    function clearFinished() {
        for (const job of jobs.filter(j => j.state === "finished")) job.dismiss();
    }

    JobViewServer {
        id: server
        // Неудачная операция должна попасться на глаза, даже если её
        // карточку прятали.
        onFinished: job => {
            if (job.error !== 0) root.hidden = root.hidden.filter(id => id !== job.id);
        }
    }

    // Удачно законченные убираем через несколько секунд.
    Timer {
        interval: 1000
        repeat: true
        running: root.jobs.some(j => j.state === "finished" && j.error === 0)
        onTriggered: {
            const now = Date.now();
            for (const job of root.jobs) {
                if (job.state === "finished" && job.error === 0 && job.id !== root.hovered
                    && now - job.ended.getTime() > 6000)
                    job.dismiss();
            }
        }
    }

    // ---- Подписи

    function plural(n, one, few, many) {
        const n10 = n % 10, n100 = n % 100;
        if (n10 === 1 && n100 !== 11) return one;
        if (n10 >= 2 && n10 <= 4 && (n100 < 12 || n100 > 14)) return few;
        return many;
    }

    // 1536 → «1,5 КБ»
    function size(bytes) {
        const units = ["Б", "КБ", "МБ", "ГБ", "ТБ"];
        let value = bytes, i = 0;
        while (value >= 1024 && i < units.length - 1) {
            value /= 1024;
            i++;
        }
        const text = i === 0 || value >= 100 ? Math.round(value).toString()
            : value.toFixed(1).replace(/\.0$/, "");
        return text.replace(".", ",") + " " + units[i];
    }

    function duration(seconds) {
        if (seconds < 60) return Math.max(1, Math.round(seconds)) + " с";
        const minutes = Math.round(seconds / 60);
        if (minutes < 60) return minutes + " мин";
        return Math.floor(minutes / 60) + " ч " + (minutes % 60) + " мин";
    }

    // file:///home/user/Загрузки → «Загрузки», домашняя папка — «Домашняя папка».
    function placeName(url) {
        if (!url) return "";
        if (!url.startsWith("file://")) return url.replace(/^[a-z]+:\/\/([^@/]*@)?/, "");
        const path = decodeURIComponent(url.substring(7)).replace(/\/+$/, "");
        if (path === Quickshell.env("HOME")) return "Домашняя папка";
        if (path === "") return "/";
        return path.substring(path.lastIndexOf("/") + 1);
    }

    // «/home/user/кот.png» или URL → «кот.png»
    function fileName(value) {
        if (!value || !(value.startsWith("/") || /^[a-z]+:\//.test(value))) return "";
        const path = decodeURIComponent(value.replace(/^file:\/\//, "")).replace(/\/+$/, "");
        return path.substring(path.lastIndexOf("/") + 1);
    }

    function appName(job) {
        const entry = job.desktopEntry !== "" ? DesktopEntries.heuristicLookup(job.desktopEntry) : null;
        return entry?.name || job.appName || job.desktopEntry;
    }

    function appIcon(job) {
        const entry = job.desktopEntry !== "" ? DesktopEntries.heuristicLookup(job.desktopEntry) : null;
        return entry?.icon || job.appIcon || "system-file-manager";
    }

    // Заголовок: «Копирование», «Готово», «Не получилось: удаление».
    function title(job) {
        const what = job.title || "Операция";
        if (job.state !== "finished") return what;
        if (job.error === 0) return "Готово";
        return "Не получилось: " + what.charAt(0).toLowerCase() + what.substring(1);
    }

    function errorText(job) {
        if (job.errorText !== "") return job.errorText;
        if (job.error === 175) return "Программа закрылась, не закончив";
        return "Ошибка " + job.error;
    }

    // Что и куда: «3 из 10 файлов → Загрузки», «кот.png → Фото».
    function body(job) {
        if (job.state === "finished" && job.error !== 0) return errorText(job);
        if (job.infoMessage !== "" && job.state !== "finished") return job.infoMessage;

        const dest = placeName(job.destUrl);
        const to = dest !== "" ? " → " + dest : "";
        const done = job.state === "finished";

        const count = (processed, total, one, few, many) => {
            if (!done && processed > 0 && processed <= total)
                return processed + " из " + total + " " + plural(total, one, few, many);
            const n = done && processed > 0 ? processed : total;
            return n + " " + plural(n, one, few, many);
        };

        if (job.totalFiles > 1) return count(job.processedFiles, job.totalFiles, "файл", "файла", "файлов") + to;
        if (job.totalItems > 1) return count(job.processedItems, job.totalItems, "объект", "объекта", "объектов") + to;

        const name = fileName(job.descriptionValue1) || fileName(job.descriptionValue2);
        if (name !== "") return name + to;
        if (job.processedFiles > 0)
            return job.processedFiles + " " + plural(job.processedFiles, "файл", "файла", "файлов") + to;
        if (dest !== "") return "В " + dest;
        return job.descriptionValue1;
    }

    // «120 МБ из 1,2 ГБ · 45 МБ/с · осталось 2 мин»
    function details(job) {
        const parts = [];
        if (job.totalBytes > 0 && job.state !== "finished")
            parts.push(size(job.processedBytes) + " из " + size(job.totalBytes));
        else if (job.processedBytes > 0)
            parts.push(size(job.processedBytes));

        if (job.state === "running" && job.speed > 0) {
            parts.push(size(job.speed) + "/с");
            if (job.totalBytes > job.processedBytes)
                parts.push("осталось " + duration((job.totalBytes - job.processedBytes) / job.speed));
        } else if (job.state === "suspended") {
            parts.push("на паузе");
        }
        return parts.join(" · ");
    }
}
