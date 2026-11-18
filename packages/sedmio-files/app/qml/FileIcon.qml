import QtQuick

// Значок файла: миниатюра, если она есть (картинки, видео, PDF), иначе
// значок типа из темы.
Item {
    id: root
    property string iconName
    property url url
    property string mimeType
    property bool canPreview: false
    property int size: 64
    property bool dimmed: false

    width: size
    height: size
    opacity: dimmed ? 0.5 : 1

    SIcon {
        anchors.centerIn: parent
        size: root.size
        name: root.iconName
        visible: thumb.status !== Image.Ready
    }

    Image {
        id: thumb
        anchors.centerIn: parent
        width: root.size
        height: root.size
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        // Мелкие значки в списке без миниатюр: незачем гонять PreviewJob.
        source: root.canPreview && root.size >= 40
            ? "image://thumb/" + encodeURIComponent(root.mimeType) + "/" + encodeURIComponent(root.url.toString())
            : ""
        sourceSize: Qt.size(256, 256)
        visible: status === Image.Ready
    }
}
