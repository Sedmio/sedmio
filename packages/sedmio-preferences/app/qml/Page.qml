import QtQuick
import QtQuick.Controls

// Раздел: заголовок и прокручиваемое содержимое; footer — полоса внизу
// (кнопки «Применить» и т. п.), не прокручивается.
Item {
    id: root
    property string title
    default property alias content: column.data
    property alias footer: footerSlot.data
    readonly property int contentWidth: Math.min(width - 64, 720)

    SText {
        id: heading
        x: 32
        y: 22
        text: root.title
        size: 24
        weight: 650
    }

    Flickable {
        id: flick
        anchors { left: parent.left; right: parent.right; top: heading.bottom; topMargin: 16; bottom: footerSlot.top }
        contentHeight: column.height + 32
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
            id: column
            x: 32
            width: root.contentWidth
            spacing: 22
        }
    }

    Item {
        id: footerSlot
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: childrenRect.height
    }
}
