pragma Singleton
import QtQuick

// pam_faillock: после нескольких неверных паролей вход закрыт на время,
// даже с верным паролем. PAM сообщает об этом «(осталось 10 минут до
// разблокировки)» / «Учетная запись заблокирована…» (или по-английски —
// смотря чья локаль). Экраны входа и блокировки переводят это в понятное.
QtObject {
    // Сообщение PAM → на сколько закрыт вход, мс (0 — сообщение не об этом).
    function duration(text) {
        const minutes = String(text).match(/(\d+)\D*(unlock|разблокир)/i);
        if (minutes) return Number(minutes[1]) * 60000;
        if (/is locked|заблокирован/i.test(text)) return 60000;
        return 0;
    }

    // Что показать, пока вход закрыт до until (Date.now() в мс).
    function notice(until) {
        const left = Math.ceil((until - Date.now()) / 60000);
        return left > 1 ? "Слишком много неверных попыток.\nПопробуйте через " + left + " мин."
                        : "Слишком много неверных попыток.\nПопробуйте чуть позже.";
    }
}
