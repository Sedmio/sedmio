import QtQuick
import QtQuick.Layouts
import Sedmio.Style

// Строка «значок — ползунок — проценты» (громкость, микрофон, яркость).
// Клик по значку — без звука; стрелка справа — подробнее.
RowLayout {
    id: root
    property string icon
    property string label             // над ползунком, если экранов несколько
    property real value
    property real maximum: 1
    property bool muted: false
    property bool hasDetails: false
    property bool iconClickable: true
    signal moved(real value)
    signal iconClicked()
    signal details()

    spacing: 6

    Rectangle {
        implicitWidth: 36
        implicitHeight: 36
        radius: 11
        color: root.iconClickable && iconArea.containsMouse ? Theme.paperDeep : Qt.alpha(Theme.paperDeep, 0)
        SIcon { anchors.centerIn: parent; name: root.icon }
        MouseArea {
            id: iconArea
            anchors.fill: parent
            enabled: root.iconClickable
            hoverEnabled: true
            onClicked: root.iconClicked()
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: -2

        SText {
            Layout.fillWidth: true
            visible: root.label !== ""
            text: root.label
            elide: Text.ElideRight
            size: 11
            color: Theme.inkMuted
        }

        SSlider {
            Layout.fillWidth: true
            value: root.value
            maximum: root.maximum
            opacity: root.muted ? 0.45 : 1
            onMoved: v => root.moved(v)
        }
    }

    SText {
        Layout.preferredWidth: 38
        horizontalAlignment: Text.AlignRight
        text: Math.round(root.maximum > 0 ? root.value / root.maximum * 100 : 0)
        font.features: ({ "tnum": 1 })
        size: 13
        weight: 550
        color: root.muted ? Theme.inkMuted : Theme.inkSoft
    }

    Rectangle {
        visible: root.hasDetails
        implicitWidth: 30
        implicitHeight: 30
        radius: 10
        color: detailsArea.containsMouse ? Theme.paperDeep : Qt.alpha(Theme.paperDeep, 0)
        SIcon { anchors.centerIn: parent; implicitSize: 16; name: "go-next" }
        MouseArea {
            id: detailsArea
            anchors.fill: parent
            hoverEnabled: true
            onClicked: root.details()
        }
    }
    // Без стрелки — место под неё, чтобы ползунки были одной длины.
    Item {
        visible: !root.hasDetails
        implicitWidth: 30
    }
}
