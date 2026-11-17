import QtQuick
import QtQuick.Window
import io.calamares.ui 1.0

// Окно, похожее на окно Calamares: полоса шагов сверху, страница,
// кнопки снизу. Страницы подставляет preview.py.
Window {
    id: win

    width: 1100
    height: 720
    visible: true
    color: "#EEF1EA"
    title: "Sedmio — предпросмотр установщика"

    Loader {
        id: sidebar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 64
        source: brandingDir + "/calamares-sidebar.qml"
    }

    Item {
        id: pageHost
        anchors.top: sidebar.bottom
        anchors.bottom: navigation.top
        anchors.left: parent.left
        anchors.right: parent.right

        // Полоса хода установки: в Calamares её рисует сам установщик
        // под слайдшоу.
        Rectangle {
            visible: ViewManager.currentStepIndex === ViewManager.execIndex
            z: 10
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 40
            anchors.horizontalCenter: parent.horizontalCenter
            width: 480
            height: 6
            radius: 3
            color: "#E3E8DE"

            Rectangle {
                width: parent.width * ViewManager.execProgress
                height: parent.height
                radius: 3
                color: "#2F5D46"
            }
        }
    }

    Loader {
        id: navigation
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: 64
        source: brandingDir + "/calamares-navigation.qml"
    }

    function attach(item, index) {
        item.parent = pageHost
        item.anchors.fill = pageHost
        item.visible = Qt.binding(function() { return index === ViewManager.currentStepIndex })
    }
}
