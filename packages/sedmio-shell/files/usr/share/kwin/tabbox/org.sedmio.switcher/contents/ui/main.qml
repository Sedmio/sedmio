import QtQuick
import org.kde.kwin as KWin

// Переключатель окон (Alt+Tab) в стиле Sedmio. Выбран в /etc/xdg/kwinrc
// ([TabBox] LayoutName). KWin грузит его в своём процессе, поэтому здесь
// только QtQuick и модуль KWin, а сам вид — в Switcher.qml через Loader:
// тот не загрузился (сломан после обновления) — показываем простой
// список окон ниже. Пакета нет совсем — KWin берёт свой стандартный.
KWin.TabBoxSwitcher {
    id: tabBox

    Instantiator {
        active: tabBox.visible
        delegate: Window {
            id: window
            flags: Qt.ToolTip | Qt.FramelessWindowHint | Qt.X11BypassWindowManagerHint
            color: "transparent"
            visible: true
            width: Math.max(1, view.item ? view.item.implicitWidth : 1)
            height: Math.max(1, view.item ? view.item.implicitHeight : 1)
            x: tabBox.screenGeometry.x + Math.round((tabBox.screenGeometry.width - width) / 2)
            y: tabBox.screenGeometry.y + Math.round((tabBox.screenGeometry.height - height) / 2)

            Loader {
                id: view
                anchors.fill: parent
                focus: true
                Component.onCompleted: setSource("Switcher.qml", { switcher: tabBox })
                onStatusChanged: if (status === Loader.Error) sourceComponent = fallback
            }

            // Иначе Qt может уронить KWin (qFatal) при сбросе видеокарты.
            onSceneGraphError: () => {}
        }
    }

    Component {
        id: fallback
        Rectangle {
            implicitWidth: 420
            implicitHeight: list.contentHeight + 24
            radius: 14
            color: "#F8FAF5"
            border.color: "#D5DCCF"
            ListView {
                id: list
                anchors { fill: parent; margins: 12 }
                model: tabBox.model
                currentIndex: tabBox.currentIndex
                onCurrentIndexChanged: tabBox.currentIndex = currentIndex
                highlight: Rectangle { radius: 8; color: "#DCE7DA" }
                highlightMoveDuration: 0
                interactive: false
                delegate: Text {
                    width: ListView.view.width
                    height: 32
                    leftPadding: 10
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                    color: "#1B251F"
                    font.pixelSize: 14
                    text: model.caption
                    MouseArea { anchors.fill: parent; onClicked: tabBox.model.activate(index) }
                }
            }
        }
    }
}
