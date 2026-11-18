import QtQuick

// Основа страницы: слева — контент, справа — растущий седум на мягком фоне.
// Дочерние элементы контента появляются по очереди: каждый с небольшой
// задержкой выезжает справа и проявляется.
Rectangle {
    id: root

    default property alias content: column.data
    property alias spacing: column.spacing
    property alias plant: sedum

    property real stage: 0          // стадия роста растения на этой странице
    property bool blooming: false
    property bool showPlant: true
    property int contentWidth: Theme.contentWidth
    property bool centerVertically: true

    color: Theme.paper

    // ---------- растение
    Item {
        id: plantArea

        visible: root.showPlant
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        // От общей ширины контента, а не от ширины этой страницы: горшок
        // на всех страницах стоит на одном месте и одного размера.
        width: parent.width - Theme.contentWidth - Theme.sideMargin * 1.5

        Backdrop { anchors.fill: parent }

        Sedum {
            id: sedum
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -10
            size: Math.min(plantArea.width * 0.95, plantArea.height * 0.95, 440)
            stage: root.stage
            blooming: root.blooming
        }
    }

    // ---------- контент
    Flickable {
        id: flick

        x: Theme.sideMargin
        width: root.showPlant ? root.contentWidth : root.width - 2 * Theme.sideMargin
        height: root.height
        contentWidth: width
        contentHeight: Math.max(height, column.implicitHeight + 96)
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        Column {
            id: column
            width: flick.width
            y: root.centerVertically ? Math.max(48, (flick.height - implicitHeight) / 2) : 48
            spacing: 28
        }
    }

    // ---------- мягкие края у прокрутки: текст не обрезается ножом,
    // а растворяется в фоне. Видны, только когда есть что прокручивать.
    component EdgeFade: Rectangle {
        property bool atTop: true
        property bool shown: false
        readonly property color clear: Qt.rgba(Theme.paper.r, Theme.paper.g, Theme.paper.b, 0)

        x: flick.x
        width: flick.width
        height: 40
        opacity: shown ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.animNormal } }
        gradient: Gradient {
            GradientStop { position: 0; color: atTop ? Theme.paper : clear }
            GradientStop { position: 1; color: atTop ? clear : Theme.paper }
        }
    }

    EdgeFade {
        atTop: true
        y: 0
        shown: flick.contentY > 4
    }
    EdgeFade {
        atTop: false
        y: root.height - height
        // Снизу у контента запас 48 px: пока скрыт только он, растворять нечего
        shown: flick.contentHeight - flick.height - flick.contentY > 48
    }

    // ---------- появление по очереди
    property var _anims: new Map()

    Component {
        id: staggerComponent

        SequentialAnimation {
            id: anim
            property Item item
            property int delay: 0

            ScriptAction { script: { anim.item.opacity = 0; anim.item.x = 28 } }
            PauseAnimation { duration: anim.delay }
            ParallelAnimation {
                NumberAnimation { target: anim.item; property: "opacity"; to: 1; duration: 480; easing.type: Easing.OutCubic }
                NumberAnimation { target: anim.item; property: "x"; to: 0; duration: 760; easing.type: Easing.OutExpo }
            }
        }
    }

    function replayAppear() {
        const kids = column.children
        for (let i = 0; i < kids.length; ++i) {
            let anim = _anims.get(kids[i])
            if (!anim) {
                anim = staggerComponent.createObject(root, { item: kids[i] })
                _anims.set(kids[i], anim)
            }
            anim.delay = i * Theme.stagger
            anim.restart()
        }
        sedum.regrow(root.stage - 1)
    }

    // Плавно прокрутить к концу страницы (например, после раскрытия блока).
    // Высота Column пересчитывается не сразу, поэтому ещё полсекунды
    // догоняем конец при каждом её изменении.
    property bool _followEnd: false

    function scrollToEnd() {
        _followEnd = true
        followTimer.restart()
        _scrollNow()
    }

    function _scrollNow() {
        scroll.to = Math.max(0, flick.contentHeight - flick.height)
        scroll.restart()
    }

    Connections {
        target: flick
        function onContentHeightChanged() { if (root._followEnd) root._scrollNow() }
    }

    Timer {
        id: followTimer
        interval: 600
        onTriggered: root._followEnd = false
    }

    NumberAnimation {
        id: scroll
        target: flick
        property: "contentY"
        duration: 520
        easing.type: Easing.OutCubic
    }

    Component.onCompleted: Qt.callLater(replayAppear)
}
