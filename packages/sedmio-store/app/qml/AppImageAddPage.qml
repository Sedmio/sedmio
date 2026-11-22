import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import Sedmio.Store
import Sedmio.Style

// Добавить AppImage: файл (перетащили, открыли из файлов, выбрали) или
// последний выпуск проекта на GitHub. Сначала — что это за программа.
Item {
    id: root
    property string file          // путь к файлу, если уже выбран
    property var info: ({})       // AppImages.inspect()
    property bool inspecting: false
    property var release: ({})    // AppImages.findRelease()
    property bool finding: false

    readonly property var job: AppImages.work["@add"] || ({})
    readonly property bool working: job.text !== undefined && (job.error || "") === ""
    signal added(string id)
    signal openExisting(string id)

    function size(bytes) {
        const mb = (bytes || 0) / 1048576;
        return mb < 10 ? mb.toFixed(1).replace(".", ",") + " МБ" : Math.round(mb) + " МБ";
    }
    function look(path) {
        root.file = path;
        root.info = {};
        root.inspecting = true;
        AppImages.inspect(path, result => {
            root.info = result;
            root.inspecting = false;
        });
    }
    Component.onCompleted: {
        if ((AppImages.work["@add"] || {}).error)
            AppImages.dismiss("@add");
        if (root.file !== "")
            look(root.file);
    }
    Connections {
        target: AppImages
        function onAdded(id) { root.added(id); }
    }

    FileDialog {
        id: picker
        title: "Выберите файл AppImage"
        nameFilters: ["AppImage (*.AppImage *.appimage)", "Все файлы (*)"]
        onAccepted: root.look(decodeURIComponent(selectedFile.toString().replace(/^file:\/\//, "")))
    }

    Flickable {
        anchors.fill: parent
        contentHeight: column.height + 48
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
            id: column
            x: Math.max(32, (root.width - width) / 2)
            width: Math.min(root.width - 64, 900)
            topPadding: 24
            spacing: 20

            SText {
                text: "Добавить AppImage"
                size: 28
                weight: 680
            }
            SText {
                width: parent.width
                wrapMode: Text.Wrap
                size: 14
                color: Theme.inkSoft
                text: "AppImage — программа одним файлом, без установки. Файл переедет в папку Applications, программа появится в меню, "
                    + "а если известно, откуда она, — будет обновляться с GitHub. Песочницы у неё нет: она может всё то же, что и вы, "
                    + "поэтому берите программы только у тех, кому доверяете."
            }

            // Идёт добавление (скачивание или разбор файла).
            Rectangle {
                visible: root.working || (root.job.error || "") !== ""
                width: parent.width
                height: progressColumn.implicitHeight + 32
                radius: Theme.radius
                color: Theme.surface
                border.width: 1
                border.color: Theme.line
                Column {
                    id: progressColumn
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
                    spacing: 8
                    SText {
                        width: parent.width
                        wrapMode: Text.Wrap
                        size: 13
                        color: root.job.error ? Theme.terracotta : Theme.inkSoft
                        text: root.job.error || root.job.text || ""
                    }
                    Rectangle {
                        visible: root.working
                        width: parent.width
                        height: 6
                        radius: 3
                        color: Theme.paperDeep
                        Rectangle {
                            height: parent.height
                            radius: 3
                            color: Theme.green
                            width: parent.width * Math.max(0.03, root.job.progress >= 0 ? root.job.progress : 0.05)
                            Behavior on width { NumberAnimation { duration: 250 } }
                        }
                    }
                    SButton {
                        text: root.working ? "Отменить" : "Понятно"
                        onClicked: root.working ? AppImages.cancel("@add") : AppImages.dismiss("@add")
                    }
                }
            }

            // Файл: что внутри.
            Rectangle {
                visible: root.file !== "" && !root.working
                width: parent.width
                height: fileColumn.implicitHeight + 32
                radius: Theme.radius
                color: Theme.surface
                border.width: 1
                border.color: Theme.line
                Column {
                    id: fileColumn
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
                    spacing: 12
                    SText {
                        visible: root.inspecting
                        text: "Смотрю, что внутри…"
                        color: Theme.inkSoft
                    }
                    SText {
                        visible: !root.inspecting && root.info.ok === false
                        width: parent.width
                        wrapMode: Text.Wrap
                        color: Theme.terracotta
                        text: (root.info.error || "") + "\n" + root.file
                    }
                    Row {
                        visible: root.info.ok === true
                        spacing: 16
                        AppIcon {
                            size: 56
                            source: root.info.icon || ""
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 3
                            SText {
                                text: root.info.name || ""
                                size: 18
                                weight: 650
                            }
                            SText {
                                width: fileColumn.width - 72
                                wrapMode: Text.Wrap
                                size: 13
                                color: Theme.inkSoft
                                text: [root.info.version ? "версия " + root.info.version : "", root.size(root.info.size), root.info.comment || ""]
                                    .filter(s => s !== "").join(" · ")
                            }
                            SText {
                                width: fileColumn.width - 72
                                elide: Text.ElideMiddle
                                size: 12
                                color: Theme.inkMuted
                                text: root.file
                            }
                        }
                    }
                    SText {
                        visible: root.info.ok === true && (root.info.existing || "") !== ""
                        width: parent.width
                        wrapMode: Text.Wrap
                        size: 13
                        color: Theme.warning
                        text: root.info.alreadyThere ? "Эта программа уже добавлена — это её файл."
                            : "Эта программа уже добавлена" + (root.info.existingVersion ? " (версия " + root.info.existingVersion + ")" : "")
                              + " — файл её заменит."
                    }
                    SText {
                        visible: root.info.ok === true && root.info.selfUpdating === true
                        width: parent.width
                        wrapMode: Text.Wrap
                        size: 13
                        color: Theme.green
                        text: "Обновляться будет с GitHub: " + (root.info.github || "") + " — так указано в самом файле."
                    }
                    Row {
                        visible: root.info.ok === true && root.info.selfUpdating !== true && !root.info.alreadyThere
                        spacing: 8
                        SText {
                            anchors.verticalCenter: parent.verticalCenter
                            size: 13
                            color: Theme.inkSoft
                            text: "Проект на GitHub (для обновлений):"
                        }
                        SField {
                            id: fileRepo
                            width: 280
                            placeholderText: "необязательно: владелец/проект"
                            text: root.info.github || ""
                            invalid: text !== "" && AppImages.parseRepo(text) === ""
                        }
                    }
                    Row {
                        spacing: 8
                        visible: !root.inspecting
                        SButton {
                            visible: root.info.ok === true && !root.info.alreadyThere
                            primary: true
                            text: (root.info.existing || "") !== "" ? "Заменить" : "Добавить в программы"
                            onClicked: {
                                if (fileRepo.invalid) return;
                                AppImages.add(root.file, root.info.selfUpdating === true ? "" : fileRepo.text);
                            }
                        }
                        SButton {
                            visible: root.info.alreadyThere === true
                            primary: true
                            text: "Открыть её страницу"
                            onClicked: root.openExisting(root.info.existing)
                        }
                        SButton {
                            text: "Другой файл…"
                            onClicked: picker.open()
                        }
                    }
                }
            }

            // Файла нет: выбрать или найти на GitHub.
            Card {
                visible: root.file === "" && !root.working
                title: "Файл на этом компьютере"
                Item {
                    width: parent.width
                    height: 64
                    SText {
                        anchors { left: parent.left; leftMargin: 16; right: chooseButton.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                        wrapMode: Text.Wrap
                        size: 13
                        color: Theme.inkSoft
                        text: "Скачанный файл .AppImage — можно и просто перетащить его в это окно."
                    }
                    SButton {
                        id: chooseButton
                        anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                        text: "Выбрать файл…"
                        onClicked: picker.open()
                    }
                }
            }
            Card {
                visible: root.file === "" && !root.working
                title: "С GitHub"
                Column {
                    width: parent.width
                    padding: 16
                    spacing: 12
                    Row {
                        spacing: 8
                        SField {
                            id: repo
                            width: 360
                            placeholderText: "ссылка на проект или владелец/проект"
                            invalid: text !== "" && AppImages.parseRepo(text) === ""
                            onAccepted: findButton.clicked()
                            onTextChanged: root.release = {}
                        }
                        SButton {
                            id: findButton
                            text: root.finding ? "Ищу…" : "Найти выпуск"
                            onClicked: {
                                if (repo.text === "" || repo.invalid || root.finding) return;
                                root.finding = true;
                                AppImages.findRelease(repo.text, result => {
                                    root.release = result;
                                    root.finding = false;
                                });
                            }
                        }
                    }
                    SText {
                        visible: root.release.ok === false
                        width: parent.width - 32
                        wrapMode: Text.Wrap
                        size: 13
                        color: Theme.terracotta
                        text: root.release.error || ""
                    }
                    Column {
                        visible: root.release.ok === true
                        width: parent.width - 32
                        spacing: 6
                        SText {
                            text: (root.release.repo || "") + " — " + (root.release.title || "")
                            weight: 600
                        }
                        SText {
                            width: parent.width
                            wrapMode: Text.Wrap
                            size: 13
                            color: Theme.inkSoft
                            text: (root.release.published ? "выпуск от " + root.release.published + " · " : "")
                                + (root.release.asset || "") + " · " + root.size(root.release.size)
                                + ((root.release.digest || "").startsWith("sha256:") ? " · контрольную сумму сверим" : "")
                        }
                        SButton {
                            primary: true
                            text: "Скачать и добавить"
                            onClicked: AppImages.addRelease(root.release)
                        }
                    }
                }
            }
        }
    }
}
