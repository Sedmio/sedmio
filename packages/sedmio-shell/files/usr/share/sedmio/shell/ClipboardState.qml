pragma Singleton
import QtQuick
import Quickshell
import org.kde.plasma.private.clipboard as Klipper

// История буфера обмена. Движок — klipper из plasma-workspace (тот же, что
// в Плазме: история в ~/.local/share/klipper, настройки в klipperrc):
// он следит за буфером и держит скопированное, когда программа, из которой
// копировали, закрылась. Показывает историю оболочка (Meta+V).
Singleton {
    id: root

    // Тип записи (HistoryItemType в klipper)
    readonly property int typeText: 2
    readonly property int typeImage: 4
    readonly property int typeUrl: 8

    readonly property alias model: history
    readonly property int count: history.count

    // Сделать запись текущим содержимым буфера (и поднять наверх).
    function select(uuid) { history.moveToTop(uuid); }
    function remove(uuid) { history.remove(uuid); }
    // Очистить всё, кроме записей со звёздочкой. Не clearHistory(): тот
    // спрашивает подтверждение окном на QtWidgets, а их в оболочке нет —
    // она падает.
    function clear() {
        const uuids = [];
        for (let i = 0; i < rows.count; i++) {
            const row = rows.objectAt(i);
            if (row && !row.starred) uuids.push(row.uuid);
        }
        for (const uuid of uuids) history.remove(uuid);
    }

    readonly property int starredCount: history.starredCount

    Klipper.HistoryModel { id: history }

    // uuid и звёздочка каждой записи — для очистки.
    Instantiator {
        id: rows
        model: history
        delegate: QtObject {
            required property string uuid
            required property bool starred
        }
    }
}
