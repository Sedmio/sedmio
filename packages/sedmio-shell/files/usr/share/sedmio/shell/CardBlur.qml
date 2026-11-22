import QtQuick
import Quickshell
import Sedmio.Style

// Размытие под карточкой всплывающего окна (меню):
//   BackgroundEffect.blurRegion: CardBlur { card: card }
// Region с item видит только место и размер карточки, а PopIn её
// увеличивает (scale) — поэтому прямоугольник считаем сами, вместе с
// масштабом. Пока карточка почти прозрачна, не размываем: иначе мелькнёт
// размытое пятно без карточки. Тема без стекла (Theme.glassOpacity 1) —
// размытия нет: под непрозрачным фоном его не видно, а KWin считал бы.
Region {
    id: root
    required property Item card
    property real cornerRadius: card.radius ?? 0

    readonly property bool shown: Theme.glassOpacity < 1 && card.visible && card.opacity > 0.3
    readonly property rect box: {
        // Зависимости: без них mapToItem не пересчитается.
        card.scale; card.x; card.y; card.width; card.height;
        const p = card.mapToItem(null, 0, 0);
        const q = card.mapToItem(null, card.width, card.height);
        return Qt.rect(p.x, p.y, q.x - p.x, q.y - p.y);
    }

    x: shown ? Math.round(box.x) : 0
    y: shown ? Math.round(box.y) : 0
    width: shown ? Math.round(box.width) : 0
    height: shown ? Math.round(box.height) : 0
    radius: Math.round(cornerRadius * card.scale)
}
