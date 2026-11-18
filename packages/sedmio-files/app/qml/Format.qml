pragma Singleton
import QtQuick

// Подписи по-русски: склонения, даты.
QtObject {
    function plural(n, one, few, many) {
        const n10 = n % 10, n100 = n % 100;
        if (n10 === 1 && n100 !== 11) return one;
        if (n10 >= 2 && n10 <= 4 && (n100 < 12 || n100 > 14)) return few;
        return many;
    }

    // 20000 → «20 000»
    function number(n) {
        return Number(n).toLocaleString(Qt.locale("ru_RU"), "f", 0);
    }

    // 3 → «3 объекта»
    function items(n) {
        return number(n) + " " + plural(n, "объект", "объекта", "объектов");
    }

    // 19 ноября 2026, 04:42 — для свойств, где нужна точная дата.
    function fullDate(value) {
        if (!value || isNaN(value.getTime())) return "";
        return value.toLocaleDateString(Qt.locale("ru_RU"), "d MMMM yyyy") + ", " + Qt.formatTime(value, "hh:mm");
    }

    // Сегодня, 14:32 · вчера, 09:10 · 3 ноября, 18:00 · 3 ноября 2024
    function date(value) {
        if (!value || isNaN(value.getTime())) return "";
        const now = new Date();
        const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
        const time = Qt.formatTime(value, "hh:mm");
        if (value >= today) return "Сегодня, " + time;
        if (value >= new Date(today - 86400000)) return "Вчера, " + time;
        if (value.getFullYear() === now.getFullYear())
            return value.toLocaleDateString(Qt.locale("ru_RU"), "d MMMM") + ", " + time;
        return value.toLocaleDateString(Qt.locale("ru_RU"), "d MMMM yyyy");
    }
}
