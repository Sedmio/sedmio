import QtQuick
import QtQuick.Shapes

// Поле пароля с круглой кнопкой «войти» справа. Пока пароль
// проверяется (busy), вместо стрелки крутится дуга. Неверный пароль —
// shake().
Rectangle {
    id: root
    property alias text: input.text
    property bool busy: false
    property bool error: false
    signal accepted()

    function focusInput() { input.forceActiveFocus(); }
    function clear() { input.text = ""; }
    function shake() { shakeAnim.restart(); }

    implicitWidth: 320
    implicitHeight: 50
    radius: 16
    color: Theme.surface
    border.width: 1
    border.color: error ? Theme.terracotta : input.activeFocus ? Theme.lineStrong : Theme.line
    Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

    TextInput {
        id: input
        anchors { left: parent.left; leftMargin: 18; right: go.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
        echoMode: TextInput.Password
        passwordCharacter: "•"
        passwordMaskDelay: 0
        readOnly: root.busy
        font.family: Theme.fontFamily
        font.pixelSize: 16
        color: Theme.ink
        selectionColor: Theme.greenWash
        selectedTextColor: Theme.ink
        clip: true
        focus: true
        Keys.onReturnPressed: root.accepted()
        Keys.onEnterPressed: root.accepted()

        SText {
            anchors.verticalCenter: parent.verticalCenter
            visible: input.text === ""
            text: "Пароль"
            size: 16
            color: Theme.inkMuted
        }
    }

    Rectangle {
        id: go
        anchors { right: parent.right; rightMargin: 7; verticalCenter: parent.verticalCenter }
        width: 36
        height: 36
        radius: 18
        color: goArea.containsMouse && !root.busy ? Qt.lighter(Theme.green, 1.12) : Theme.green
        opacity: input.text !== "" || root.busy ? 1 : 0.35
        Behavior on opacity { NumberAnimation { duration: Theme.animFast } }

        // Стрелка
        Shape {
            anchors.centerIn: parent
            width: 16
            height: 16
            visible: !root.busy
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: Theme.textOnGreen
                strokeWidth: 2
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                startX: 2; startY: 8
                PathLine { x: 14; y: 8 }
                PathMove { x: 9; y: 3 }
                PathLine { x: 14; y: 8 }
                PathLine { x: 9; y: 13 }
            }
        }

        // Ожидание
        Shape {
            anchors.centerIn: parent
            width: 18
            height: 18
            visible: root.busy
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: Theme.textOnGreen
                strokeWidth: 2
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                PathAngleArc { centerX: 9; centerY: 9; radiusX: 7; radiusY: 7; startAngle: 0; sweepAngle: 270 }
            }
            RotationAnimation on rotation {
                running: root.busy
                from: 0; to: 360
                duration: 900
                loops: Animation.Infinite
            }
        }

        MouseArea {
            id: goArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { if (!root.busy) root.accepted(); input.forceActiveFocus(); }
        }
    }

    SequentialAnimation {
        id: shakeAnim
        NumberAnimation { target: root; property: "anchors.horizontalCenterOffset"; to: -10; duration: 50 }
        NumberAnimation { target: root; property: "anchors.horizontalCenterOffset"; to: 9; duration: 70 }
        NumberAnimation { target: root; property: "anchors.horizontalCenterOffset"; to: -6; duration: 60 }
        NumberAnimation { target: root; property: "anchors.horizontalCenterOffset"; to: 3; duration: 50 }
        NumberAnimation { target: root; property: "anchors.horizontalCenterOffset"; to: 0; duration: 40 }
    }
}
