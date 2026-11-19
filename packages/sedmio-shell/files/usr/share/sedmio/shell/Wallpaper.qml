import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Sedmio.Style

// Обои под всеми окнами: картинка, выбранная в «Параметрах»
// (WallpaperState), или свои обои Sedmio — мягкий градиент и знак. Новая
// картинка проявляется поверх старой, когда загрузится; не открылась —
// остаются обои Sedmio.
PanelWindow {
    id: root
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    color: Theme.paperDeep
    WlrLayershell.layer: WlrLayer.Background
    // «desktop» — KWin по этому имени считает слой рабочим столом (как
    // обои plasmashell): обзор окон (Meta+W), «Показать рабочий стол» и
    // эффекты рисуют наши обои, а не чёрный фон.
    WlrLayershell.namespace: "desktop"

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: Theme.wallpaperTop }
            GradientStop { position: 0.55; color: Theme.wallpaperMiddle }
            GradientStop { position: 1.0; color: Theme.wallpaperBottom }
        }
    }

    IconImage {
        readonly property int size: Math.min(root.width, root.height) * 0.36
        implicitSize: size
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: root.width * 0.08
        anchors.bottomMargin: root.height * 0.1
        source: Icons.path("sedmio", true)
        opacity: 0.13
        visible: layerA.status !== Image.Ready && layerB.status !== Image.Ready
    }

    // Две картинки по очереди: новая грузится в заднюю и проявляется, когда
    // готова, — без мигания градиентом. Не открылась — обои Sedmio.
    property int front: 0
    readonly property string wanted: WallpaperState.image === "" ? ""
        : "file://" + WallpaperState.image.split("/").map(encodeURIComponent).join("/")
    function show() {
        const back = front === 0 ? layerB : layerA;
        if (wanted === "") {
            layerA.source = "";
            layerB.source = "";
            if (WallpaperState.loaded) WallpaperState.shown = true;
        } else if (back.source.toString() === wanted && back.status === Image.Ready) {
            front = 1 - front;
        } else {
            back.source = wanted;
        }
    }
    onWantedChanged: show()
    Connections {
        target: WallpaperState
        function onLoadedChanged() { root.show(); }
    }
    // Старая картинка уже не видна — отпустить её память.
    onFrontChanged: dropBack.restart()
    Timer {
        id: dropBack
        interval: 600
        onTriggered: (root.front === 0 ? layerB : layerA).source = ""
    }
    Component.onCompleted: show()

    component Layer: Image {
        required property int number
        readonly property bool isFront: root.front === number
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        // Не больше экрана: огромная фотография иначе съест память.
        sourceSize: Qt.size(root.width * root.screen.devicePixelRatio, root.height * root.screen.devicePixelRatio)
        asynchronous: true
        cache: false
        smooth: true
        z: isFront ? 2 : 1
        opacity: isFront && status === Image.Ready ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.InOutQuad } }
        onStatusChanged: {
            if (source.toString() !== root.wanted)
                return;
            if (status === Image.Ready) {
                if (!isFront) root.front = number;
                WallpaperState.shown = true;
            } else if (status === Image.Error) {
                console.warn("Обои не открылись:", source);
                layerA.source = "";
                layerB.source = "";
                WallpaperState.shown = true;
            }
        }
    }
    Layer { id: layerA; number: 0 }
    Layer { id: layerB; number: 1 }

    // Правый клик — меню рабочего стола.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        onClicked: event => desktopMenu.openAt(event.x, event.y)
    }

    DesktopMenu {
        id: desktopMenu
        window: root
    }
}
