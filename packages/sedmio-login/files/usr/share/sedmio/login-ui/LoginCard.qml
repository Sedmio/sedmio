import QtQuick
import QtQuick.Shapes
import org.kde.plasma.private.keyboardindicator as KeyboardIndicator
import Sedmio.Style

// Кто входит: аватар, имя, поле пароля и строка сообщения под ним.
// Сам пароль никуда не отправляет — submitted(password), дальше решает
// экран (greetd или kscreenlocker); он же задаёт message.
// Неверный пароль — rejected(): поле очищается и вздрагивает.
Column {
    id: root
    property string displayName
    property url avatar
    property bool busy: false
    property string message
    property bool messageIsError: false
    // Пользователей несколько — стрелки по бокам имени.
    property bool canSwitch: false
    property alias password: box.text

    signal submitted(string password)
    signal edited()
    signal previousUser()
    signal nextUser()

    function focusInput() { box.focusInput(); }
    function rejected() {
        box.clear();
        box.shake();
        box.focusInput();
    }

    spacing: 0
    width: 360

    KeyboardIndicator.KeyState {
        id: capsLock
        key: Qt.Key_CapsLock
    }

    Avatar {
        anchors.horizontalCenter: parent.horizontalCenter
        source: root.avatar
        name: root.displayName
    }

    Item { width: 1; height: 14 }

    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 10

        SwitchArrow { visible: root.canSwitch; back: true; onClicked: root.previousUser() }
        SText {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, root.width - 100)
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: root.displayName
            size: 22
            weight: 600
        }
        SwitchArrow { visible: root.canSwitch; onClicked: root.nextUser() }
    }

    Item { width: 1; height: 22 }

    PasswordBox {
        id: box
        anchors.horizontalCenter: parent.horizontalCenter
        width: 320
        busy: root.busy
        error: root.messageIsError && root.message !== ""
        // Пустой пароль тоже отправляем: у live (и вообще бывает) его нет.
        onAccepted: if (!root.busy) root.submitted(text)
        onTextChanged: if (text !== "") root.edited()
    }

    Item { width: 1; height: 12 }

    SText {
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width
        // Две строки места всегда: длинное сообщение не сдвигает карточку.
        height: 36
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignTop
        wrapMode: Text.WordWrap
        maximumLineCount: 2
        elide: Text.ElideRight
        size: 13
        weight: root.messageIsError ? 550 : 400
        color: root.messageIsError ? Theme.terracotta : Theme.inkSoft
        text: root.message !== "" ? root.message : capsLock.locked ? "Включён Caps Lock" : ""
    }

    // Круглая кнопка-шеврон рядом с именем.
    component SwitchArrow: Rectangle {
        id: arrow
        property bool back: false
        signal clicked()
        anchors.verticalCenter: parent.verticalCenter
        width: 30
        height: 30
        radius: 15
        color: arrowArea.containsMouse ? Theme.surface : "transparent"
        border.width: arrowArea.containsMouse ? 1 : 0
        border.color: Theme.line
        Behavior on color { ColorAnimation { duration: Theme.animFast } }

        Shape {
            anchors.centerIn: parent
            width: 8
            height: 12
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: arrowArea.containsMouse ? Theme.ink : Theme.inkMuted
                strokeWidth: 2
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                startX: arrow.back ? 7 : 1; startY: 1
                PathLine { x: arrow.back ? 1 : 7; y: 6 }
                PathLine { x: arrow.back ? 7 : 1; y: 11 }
            }
        }
        MouseArea {
            id: arrowArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: arrow.clicked()
        }
    }
}
