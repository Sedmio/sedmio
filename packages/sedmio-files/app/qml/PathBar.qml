import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Sedmio.Files
import Sedmio.Style

// Строка адреса: путь кусочками (Домашняя папка › Фото › 2026), каждый
// кликабелен. Клик по пустому месту или Ctrl+L — ввести путь текстом.
Rectangle {
    id: root
    property url url
    signal openRequested(url url)
    signal openInNewTabRequested(url url)

    readonly property bool editing: field.visible

    function edit() {
        field.text = FileOps.prettyPath(root.url);
        field.visible = true;
        field.forceActiveFocus();
        field.selectAll();
    }

    implicitHeight: 36
    radius: 10
    color: Theme.surface
    border.width: 1
    border.color: field.activeFocus ? Theme.lineStrong : Theme.line

    MouseArea {
        anchors.fill: parent
        onClicked: root.edit()
    }

    // Кусочки пути; не влезают — видна правая часть (текущая папка).
    Flickable {
        id: flick
        anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
        visible: !field.visible
        clip: true
        contentWidth: crumbsRow.width
        flickableDirection: Flickable.HorizontalFlick
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentWidth > width
        onContentWidthChanged: contentX = Math.max(0, contentWidth - width)
        onWidthChanged: contentX = Math.max(0, contentWidth - width)

        Row {
            id: crumbsRow
            readonly property int count: crumbs.count
            height: flick.height
            spacing: 0

            Repeater {
                id: crumbs
                model: FileOps.crumbs(root.url)

                Row {
                    required property var modelData
                    required property int index
                    height: crumbsRow.height

                    SText {
                        visible: parent.index > 0
                        anchors.verticalCenter: parent.verticalCenter
                        text: "›"
                        leftPadding: 2
                        rightPadding: 2
                        color: Theme.inkMuted
                    }

                    Rectangle {
                        // Текущая папка не влезает даже одна — с многоточием,
                        // а не обрезанная посреди слова.
                        readonly property bool last: parent.index === crumbsRow.count - 1
                        anchors.verticalCenter: parent.verticalCenter
                        width: last ? Math.min(crumb.implicitWidth + 16, flick.width) : crumb.implicitWidth + 16
                        height: 26
                        radius: 7
                        color: crumbArea.containsMouse ? Theme.paperDeep : "transparent"

                        SText {
                            id: crumb
                            anchors.centerIn: parent
                            width: Math.min(implicitWidth, parent.width - 16)
                            elide: Text.ElideRight
                            text: parent.parent.modelData.name
                            weight: parent.last ? 600 : 400
                        }
                        MouseArea {
                            id: crumbArea
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                            onClicked: mouse => mouse.button === Qt.MiddleButton
                                ? root.openInNewTabRequested(parent.parent.modelData.url)
                                : root.openRequested(parent.parent.modelData.url)
                        }
                    }
                }
            }
        }
    }

    TextField {
        id: field
        anchors { fill: parent; leftMargin: 4; rightMargin: 4 }
        visible: false
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontBody
        color: Theme.ink
        selectionColor: Theme.greenSelect
        selectedTextColor: Theme.ink
        background: null
        verticalAlignment: TextInput.AlignVCenter

        onAccepted: {
            visible = false;
            root.openRequested(FileOps.urlFromInput(text));
        }
        onActiveFocusChanged: if (!activeFocus) visible = false
        Keys.onEscapePressed: visible = false
    }
}
