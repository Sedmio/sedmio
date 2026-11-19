pragma Singleton
import QtQuick
import Quickshell
import Sedmio.Style

// Адрес значка из темы значков — для всех значков оболочки.
//
// Значки-символы (звук, колокольчик, поиск) KDE перекрашивает под палитру,
// а готовую картинку Qt кэширует по адресу: после смены темы на ходу они
// остались бы прежнего цвета (тёмные на тёмной панели). Поэтому в адресе —
// номер палитры: сменилась — новый адрес, значок рисуется заново.
// «?path=» провайдер Quickshell смотрит, только если значка нет в теме,
// и до него обрезает имя — сам значок суффикс не меняет.
Singleton {
    // fallback: имя запасного значка; true — нет значка в теме → "".
    function path(name, fallback) {
        let url;
        if (fallback === true)
            url = name ? Quickshell.iconPath(name, true) : "";
        else if (fallback)
            // Проверка через iconPath(…, true), а не hasThemeIcon: та
            // не признаёт абсолютный путь (Icon=/opt/… у AppImage, игр).
            url = (name && Quickshell.iconPath(name, true)) || Quickshell.iconPath(fallback);
        else
            url = name ? Quickshell.iconPath(name) : "";
        return url === "" ? "" : url + "?path=/palette-" + Theme.paletteSerial;
    }

    // Готовый адрес значка от программы (трей): к «image://icon/имя» —
    // тот же номер палитры. С «?path=» (своя папка значков программы) и
    // картинки (image://qsimage) — как есть: их KDE не перекрашивает.
    function themed(url) {
        if (!url || !url.startsWith("image://icon/") || url.includes("?")) return url;
        return url + "?path=/palette-" + Theme.paletteSerial;
    }
}
