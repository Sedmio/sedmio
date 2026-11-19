import QtQuick
import QtQuick.Layouts
import Quickshell
import Sedmio.Style

// История буфера обмена: поиск, список скопированного (текст, картинки,
// файлы); записи со звёздочкой «Очистить» не трогает. Enter или клик кладёт
// запись в буфер, окно закрывается и фокус возвращается программе —
// остаётся нажать Ctrl+V. Подложку рисует EdgeDrawerShape в слое рамки.
Item {
    id: root
    property bool open: false
    property real maxHeight: 640
    signal closeRequested(bool restoreFocus)

    readonly property real listHeight: Math.min(list.contentHeight, maxHeight - field.height - footer.height - 24)
    readonly property real wantedHeight: field.height + 12 + (list.count > 0 ? listHeight : empty.implicitHeight)
        + 12 + footer.height

    onOpenChanged: {
        if (!open) return;
        search.text = "";
        list.currentIndex = 0;
        list.positionViewAtBeginning();
        search.forceActiveFocus();
    }

    function selectCurrent() {
        const item = list.currentItem;
        if (!item) return;
        ClipboardState.select(item.entry.id);
        root.closeRequested(true);
    }

    // file:///home/user/Фото/кот.png → «кот.png»
    function fileNames(urls) {
        return urls.map(u => {
            const path = decodeURIComponent(u.replace(/^file:\/\//, ""));
            return path.endsWith("/") ? path : path.substring(path.lastIndexOf("/") + 1);
        });
    }

    // Поле поиска
    Rectangle {
        id: field
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: 46
        radius: 14
        color: Theme.surface
        border.color: search.activeFocus ? Theme.lineStrong : Theme.line
        border.width: 1

        SIcon {
            id: searchIcon
            anchors.verticalCenter: parent.verticalCenter
            x: 15
            implicitSize: 18
            name: "search"
            opacity: 0.7
        }

        TextInput {
            id: search
            anchors { left: searchIcon.right; leftMargin: 11; right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
            font.family: Theme.fontFamily
            font.pixelSize: 15
            color: Theme.ink
            selectionColor: Theme.greenWash
            selectedTextColor: Theme.ink
            clip: true

            onTextChanged: {
                list.currentIndex = 0;
                list.positionViewAtBeginning();
            }

            Keys.onPressed: event => {
                switch (event.key) {
                case Qt.Key_Escape:
                    root.closeRequested(true);
                    break;
                case Qt.Key_Return:
                case Qt.Key_Enter:
                    root.selectCurrent();
                    break;
                case Qt.Key_Down:
                case Qt.Key_Tab:
                    list.incrementCurrentIndex();
                    break;
                case Qt.Key_Up:
                case Qt.Key_Backtab:
                    list.decrementCurrentIndex();
                    break;
                case Qt.Key_PageDown:
                    list.currentIndex = Math.min(list.count - 1, list.currentIndex + 5);
                    break;
                case Qt.Key_PageUp:
                    list.currentIndex = Math.max(0, list.currentIndex - 5);
                    break;
                case Qt.Key_Delete:
                    // Пока в поиске пусто — Delete удаляет запись, иначе символ.
                    if (search.text !== "" || !list.currentItem) return;
                    ClipboardState.remove(list.currentItem.entry.id);
                    break;
                default:
                    return;
                }
                event.accepted = true;
            }

            SText {
                anchors.verticalCenter: parent.verticalCenter
                visible: search.text === ""
                text: "Найти в буфере обмена"
                color: Theme.inkMuted
                size: 15
            }
        }
    }

    ListView {
        id: list
        anchors { top: field.bottom; topMargin: 12; left: parent.left; right: parent.right }
        height: root.listHeight
        visible: count > 0
        clip: true
        spacing: 4
        boundsBehavior: Flickable.StopAtBounds
        highlightMoveDuration: Theme.animFast
        highlightMoveVelocity: -1
        highlightFollowsCurrentItem: true
        keyNavigationWraps: true

        model: ScriptModel {
            values: ClipboardState.search(search.text)
        }

        highlight: Rectangle {
            radius: Theme.radius
            color: Theme.greenWash
        }

        delegate: Item {
            id: row
            required property var modelData
            required property int index
            readonly property var entry: modelData

            readonly property bool current: entry.id === ClipboardState.currentId
            readonly property bool hovered: mouse.containsMouse || starArea.containsMouse || removeArea.containsMouse

            width: ListView.view.width
            height: Math.max(48, body.implicitHeight + 20)

            Rectangle {
                anchors.fill: parent
                radius: Theme.radius
                color: Theme.paperDeep
                visible: row.hovered && list.currentIndex !== row.index
            }

            MouseArea {
                id: mouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: {
                    list.currentIndex = row.index;
                    root.selectCurrent();
                }
            }

            Item {
                id: body
                anchors { left: parent.left; leftMargin: 12; right: buttons.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                implicitHeight: row.entry.kind === "image" ? image.height
                    : row.entry.kind === "files" ? files.implicitHeight : text.implicitHeight

                // Текст: первые строки
                SText {
                    id: text
                    visible: row.entry.kind === "text"
                    width: parent.width
                    text: row.entry.text.replace(/\s+$/, "").substring(0, 400)
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                    size: 14
                    lineHeight: 1.1
                }

                // Картинка: миниатюра и размер
                Row {
                    visible: row.entry.kind === "image"
                    spacing: 12
                    Image {
                        id: image
                        height: Math.min(72, Math.max(24, row.entry.imageSize.height))
                        width: Math.min(200, row.entry.imageSize.height > 0
                            ? height * row.entry.imageSize.width / row.entry.imageSize.height : height)
                        source: row.entry.image
                        sourceSize.height: 144
                        fillMode: Image.PreserveAspectFit
                        cache: false
                        asynchronous: true
                    }
                    SText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Картинка " + row.entry.imageSize.width + "×" + row.entry.imageSize.height
                        size: Theme.fontSmall
                        color: Theme.inkMuted
                    }
                }

                // Файлы: значок и имена
                RowLayout {
                    id: files
                    visible: row.entry.kind === "files"
                    width: parent.width
                    spacing: 10
                    readonly property var names: row.entry.kind === "files" ? root.fileNames(row.entry.files) : []
                    SIcon {
                        implicitSize: 22
                        name: files.names.length > 1 ? "folder-documents" : "text-x-generic"
                    }
                    SText {
                        Layout.fillWidth: true
                        text: files.names.length > 3
                            ? files.names.slice(0, 3).join(", ") + " и ещё " + (files.names.length - 3)
                            : files.names.join(", ")
                        elide: Text.ElideMiddle
                        size: 14
                    }
                }
            }

            // Справа: «сейчас в буфере», звёздочка, удалить
            Row {
                id: buttons
                anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
                spacing: 2

                SText {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: row.current && !row.hovered
                    rightPadding: 6
                    text: "в буфере"
                    size: 12
                    color: Theme.inkMuted
                }

                Rectangle {
                    width: 30
                    height: 30
                    radius: 9
                    visible: row.entry.starred || row.hovered || list.currentIndex === row.index
                    color: starArea.containsMouse ? Theme.paper : Qt.alpha(Theme.paper, 0)
                    SIcon {
                        anchors.centerIn: parent
                        implicitSize: 16
                        name: row.entry.starred ? "starred-symbolic" : "non-starred-symbolic"
                        opacity: row.entry.starred ? 1 : 0.6
                    }
                    MouseArea {
                        id: starArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: row.entry.starred = !row.entry.starred
                    }
                }

                Rectangle {
                    width: 30
                    height: 30
                    radius: 9
                    visible: row.hovered || list.currentIndex === row.index
                    color: removeArea.containsMouse ? Theme.paper : Qt.alpha(Theme.paper, 0)
                    SIcon {
                        anchors.centerIn: parent
                        implicitSize: 16
                        name: "edit-delete"
                        opacity: 0.7
                    }
                    MouseArea {
                        id: removeArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: ClipboardState.remove(row.entry.id)
                    }
                }
            }
        }
    }

    // Пусто или ничего не нашлось
    ColumnLayout {
        id: empty
        anchors { top: field.bottom; topMargin: 24; horizontalCenter: parent.horizontalCenter }
        visible: list.count === 0
        spacing: 6

        SIcon {
            Layout.alignment: Qt.AlignHCenter
            implicitSize: 36
            name: "edit-paste"
            opacity: 0.35
        }
        SText {
            Layout.alignment: Qt.AlignHCenter
            Layout.bottomMargin: 12
            text: search.text !== "" ? "Ничего не нашлось" : "Здесь будет всё, что вы скопируете"
            color: Theme.inkMuted
        }
    }

    // Подсказка и очистка
    RowLayout {
        id: footer
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 4 }
        height: 34
        spacing: 8

        SText {
            Layout.fillWidth: true
            text: "Enter — в буфер, потом Ctrl+V · Delete — убрать"
            elide: Text.ElideRight
            size: 12
            color: Theme.inkMuted
        }
        SButton {
            // Во время поиска не показывать: очистило бы и то, чего не видно.
            visible: search.text === "" && ClipboardState.count > ClipboardState.starredCount
            text: ClipboardState.starredCount > 0 ? "Очистить, кроме ★" : "Очистить"
            onClicked: ClipboardState.clear()
        }
    }
}
