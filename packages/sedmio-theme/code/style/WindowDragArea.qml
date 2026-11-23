import QtQuick

// Место, за которое окно таскают, как за заголовок: потянуть — переместить,
// двойной щелчок — развернуть или вернуть размер. Ставить первым (ниже
// всего) поперёк верха окна: кнопки и поля поверх него берут щелчки себе.
Item {
    id: root
    readonly property Window win: Window.window

    DragHandler {
        target: null
        acceptedButtons: Qt.LeftButton
        onActiveChanged: if (active && root.win) root.win.startSystemMove()
    }
    TapHandler {
        acceptedButtons: Qt.LeftButton
        onDoubleTapped: {
            if (!root.win) return;
            if (root.win.visibility === Window.Maximized) root.win.showNormal();
            else root.win.showMaximized();
        }
    }
}
