import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Sedmio.Files
import Sedmio.Style

// Просмотр по пробелу: картинка, текст или большая миниатюра (видео, PDF)
// поверх папки. Стрелки — соседние файлы, пробел или Esc — закрыть,
// Enter — открыть программой.
Popup {
    id: look
    property FolderModel folder
    property int row: -1
    property var info: ({})
    readonly property string kind: info.isDir ? "dir" : FileOps.previewKind(info.mimeType ?? "")

    // Перешли стрелками к другому файлу — выделить его и в папке.
    signal rowChosen(int row)
    signal openRequested(int row)

    function show(r) {
        if (!folder || r < 0 || r >= folder.count) return;
        row = r;
        info = folder.infoAt(r);
        open();
    }
    function step(delta) {
        const r = Math.max(0, Math.min(folder.count - 1, row + delta));
        if (r === row) return;
        row = r;
        info = folder.infoAt(r);
        rowChosen(r);
    }

    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(parent.width - 64, 1200)
    height: parent.height - 64
    modal: true
    focus: true
    padding: 0
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    Overlay.modal: Rectangle { color: Qt.rgba(0.11, 0.14, 0.12, 0.45) }

    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.animFast }
        NumberAnimation { property: "scale"; from: 0.97; to: 1; duration: Theme.animFast; easing.type: Easing.OutCubic }
    }
    exit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 90 } }

    background: Rectangle {
        radius: 16
        color: Theme.surface
        border.width: 1
        border.color: Theme.line
    }

    contentItem: FocusScope {
        focus: true

        Keys.onPressed: event => {
            switch (event.key) {
            case Qt.Key_Space: look.close(); break;
            case Qt.Key_Left:
            case Qt.Key_Up: look.step(-1); break;
            case Qt.Key_Right:
            case Qt.Key_Down: look.step(1); break;
            case Qt.Key_Home: look.step(-look.row); break;
            case Qt.Key_End: look.step(look.folder.count); break;
            case Qt.Key_Return:
            case Qt.Key_Enter:
                look.openRequested(look.row);
                look.close();
                break;
            default: return;
            }
            event.accepted = true;
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // Что это и что с ним сделать
            RowLayout {
                Layout.fillWidth: true
                Layout.margins: 14
                spacing: 12

                FileIcon {
                    size: 32
                    iconName: look.info.iconName ?? ""
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    SText {
                        Layout.fillWidth: true
                        elide: Text.ElideMiddle
                        size: 15
                        weight: 600
                        text: look.info.name ?? ""
                    }
                    SText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        size: Theme.fontSmall
                        color: Theme.inkMuted
                        text: {
                            const i = look.info;
                            const parts = [i.typeText ?? ""];
                            if (i.isDir && i.childCount >= 0) parts.push(Format.items(i.childCount));
                            else if (i.size >= 0) parts.push(FileOps.formatSize(i.size));
                            parts.push(Format.date(i.modified));
                            return parts.filter(p => p !== "").join(" · ");
                        }
                    }
                }
                SButton {
                    text: look.info.isDir ? "Открыть папку" : "Открыть"
                    onClicked: {
                        look.openRequested(look.row);
                        look.close();
                    }
                }
                ToolButton {
                    icon: "window-close"
                    hint: "Закрыть"
                    onClicked: look.close()
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Theme.line
            }

            // Сам файл
            Loader {
                id: body
                Layout.fillWidth: true
                Layout.fillHeight: true
                // Новый файл — новый вид, чтобы не мелькал прошлый.
                sourceComponent: !look.opened && !look.visible ? null
                    : look.kind === "image" ? imageView
                    : look.kind === "text" ? textView
                    : look.kind === "thumb" ? thumbView
                    : cardView
                onLoaded: if (item) item.url = look.info.url
                Connections {
                    target: look
                    function onInfoChanged() { if (body.item) body.item.url = look.info.url; }
                }
            }
        }
    }

    // ---- Виды

    Component {
        id: imageView
        Item {
            property url url
            readonly property bool animated: /image\/(gif|webp|apng)/.test(look.info.mimeType ?? "")
            AnimatedImage {
                anchors { fill: parent; margins: 16 }
                visible: parent.animated
                source: parent.animated ? parent.url : ""
                fillMode: implicitWidth <= width && implicitHeight <= height ? Image.Pad : Image.PreserveAspectFit
                asynchronous: true
            }
            Image {
                id: picture
                anchors { fill: parent; margins: 16 }
                visible: !parent.animated
                source: parent.animated ? "" : parent.url
                // Мелкие — в родном размере, растянутые они мылятся.
                fillMode: implicitWidth <= width && implicitHeight <= height ? Image.Pad : Image.PreserveAspectFit
                asynchronous: true
                autoTransform: true
                smooth: true
                mipmap: true
                // Большие фото — не в полном размере, а под окно.
                sourceSize: Qt.size(Math.ceil(width * Screen.devicePixelRatio), Math.ceil(height * Screen.devicePixelRatio))
            }
            FileIcon {
                anchors.centerIn: parent
                visible: picture.status === Image.Error
                size: 128
                iconName: look.info.iconName ?? ""
            }
        }
    }

    Component {
        id: textView
        Item {
            id: textRoot
            property url url
            readonly property var content: FileOps.readText(url)
            ScrollView {
                anchors.fill: parent
                anchors.bottomMargin: note.visible ? note.height : 0
                TextArea {
                    readOnly: true
                    // Стрелки и пробел остаются у просмотра, выделять мышью можно.
                    activeFocusOnPress: false
                    selectByMouse: true
                    wrapMode: TextEdit.Wrap
                    textFormat: TextEdit.PlainText
                    font.family: "monospace"
                    font.pixelSize: 13
                    color: Theme.ink
                    selectionColor: Theme.greenSelect
                    selectedTextColor: Theme.ink
                    padding: 16
                    background: null
                    text: textRoot.content.text ?? ""
                }
            }
            SText {
                id: note
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 10 }
                visible: !!textRoot.content.truncated
                horizontalAlignment: Text.AlignHCenter
                size: Theme.fontSmall
                color: Theme.inkMuted
                text: "Показано начало файла"
            }
        }
    }

    Component {
        id: thumbView
        Item {
            property url url
            Image {
                id: big
                anchors { fill: parent; margins: 16 }
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                source: "image://thumb/" + encodeURIComponent(look.info.mimeType ?? "") + "/" + encodeURIComponent(parent.url.toString())
                sourceSize: Qt.size(1024, 1024)
            }
            FileIcon {
                anchors.centerIn: parent
                visible: big.status !== Image.Ready
                size: 128
                iconName: look.info.iconName ?? ""
            }
        }
    }

    // Папки и всё, что не показать: большой значок и сведения.
    Component {
        id: cardView
        Item {
            property url url
            ColumnLayout {
                anchors.centerIn: parent
                width: Math.min(parent.width - 48, 420)
                spacing: 10
                FileIcon {
                    Layout.alignment: Qt.AlignHCenter
                    size: 128
                    iconName: look.info.iconName ?? ""
                    url: look.info.url ?? ""
                    mimeType: look.info.mimeType ?? ""
                    canPreview: !!look.info.canPreview
                }
                SText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WrapAnywhere
                    size: 17
                    weight: 600
                    text: look.info.name ?? ""
                }
                SText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    color: Theme.inkMuted
                    text: look.info.typeText ?? ""
                }
            }
        }
    }
}
