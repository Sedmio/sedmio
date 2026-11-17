import QtQuick
import io.calamares.ui 1.0
import io.calamares.core 1.0
import "components"

// Кнопки снизу (navigation: qml,bottom): «Отмена» слева тихо,
// «Назад» и главное действие справа.
Rectangle {
    id: nav

    height: 64
    color: Theme.paper

    // В подписях Calamares есть «&» для горячих клавиш: «&Далее».
    function clean(label) {
        return (label || "").replace("&", "")
    }

    SButton {
        anchors.left: parent.left
        anchors.leftMargin: Theme.sideMargin - 18
        anchors.verticalCenter: parent.verticalCenter
        text: nav.clean(ViewManager.quitLabel)
        visible: ViewManager.quitVisible
        enabled: ViewManager.quitEnabled
        onClicked: ViewManager.quit()
    }

    Row {
        anchors.right: parent.right
        anchors.rightMargin: Theme.sideMargin
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8
        visible: ViewManager.backAndNextVisible

        SButton {
            text: nav.clean(ViewManager.backLabel)
            visible: ViewManager.backEnabled
            onClicked: ViewManager.back()
        }
        SButton {
            primary: true
            text: nav.clean(ViewManager.nextLabel)
            enabled: ViewManager.nextEnabled
            onClicked: ViewManager.next()
        }
    }
}
