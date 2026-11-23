pragma Singleton
import QtQuick
import qs
import Quickshell
import Quickshell.Wayland

// История буфера обмена. Движок свой — ClipboardHistory в нашем Quickshell
// (протокол ext-data-control): он запоминает скопированное (текст, картинки,
// файлы) в ~/.local/share/quickshell/clipboard и держит буфер заполненным,
// когда программа, из которой копировали, закрылась. Показывает историю
// оболочка (Meta+V).
Singleton {
    id: root

    // Новые сверху
    readonly property var entries: ClipboardHistory.entries.values
    readonly property string currentId: ClipboardHistory.currentId
    readonly property int count: entries.length
    readonly property int starredCount: entries.filter(e => e.starred).length

    // Поиск по тексту (у файлов — по путям), без учёта регистра.
    function search(query) {
        const q = query.trim().toLowerCase();
        if (q === "") return entries;
        return entries.filter(e => e.text.toLowerCase().includes(q));
    }

    // Сделать запись текущим содержимым буфера (и поднять наверх).
    function select(id) { ClipboardHistory.select(id); }
    function remove(id) { ClipboardHistory.remove(id); }
    // Всё, кроме записей со звёздочкой.
    function clear() { ClipboardHistory.clear(); }
}
