import QtQuick
import QtQuick.Controls
import Sedmio.Store
import Sedmio.Style

// Пакет из AUR. Собрать и поставить можно, только посмотрев PKGBUILD:
// это скрипт от незнакомого человека, и выполнится он на этом компьютере.
//
// Ещё — установленный пакет, которого нет в каталоге (из «Удалить» в меню
// оболочки): repo — из репозиториев Arch, AUR не спрашиваем.
Item {
    id: root
    property string name
    property bool repo: false
    property string title       // имя программы из меню, если знаем
    property string iconName
    property var info: ({})
    property bool loading: true
    property string pkgbuild
    property string pkgbuildError
    property bool reviewed: false
    property bool confirmRemove: false

    readonly property string installedVersion: Catalog.revision >= 0 && Catalog.ready ? Aur.installedVersion(name) : ""
    readonly property var job: Jobs.list.length >= 0 ? Jobs.forApp("aur:" + name) : ({})
    readonly property bool working: job.state === "waiting" || job.state === "running"
    readonly property bool hasUpdate: installedVersion !== "" && info.version !== undefined && Aur.newer(info.version, installedVersion)

    signal openUpdates()

    readonly property bool known: info.name !== undefined || installedVersion !== ""

    Component.onCompleted: {
        if (repo) {
            loading = false;
            return;
        }
        Aur.info(name, result => {
            root.info = result;
            root.loading = false;
        });
    }
    function showPkgbuild() {
        Aur.pkgbuild(info.base || name, (text, error) => {
            root.pkgbuild = text;
            root.pkgbuildError = error;
            root.reviewed = text !== "";
        });
    }

    Flickable {
        id: flick
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

            Row {
                spacing: 20
                SIcon {
                    name: root.iconName || "package-x-generic"
                    size: 72
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4
                    SText {
                        text: root.title || root.name
                        size: 28
                        weight: 680
                    }
                    SText {
                        text: root.loading ? "Загружаю сведения из AUR…"
                            : root.repo ? "Пакет " + root.name + " из репозиториев Arch"
                            : root.info.error ? root.info.error
                            : root.info.name === undefined ? (root.installedVersion !== "" ? "Пакет " + root.name + " поставлен не из репозиториев, в AUR его нет" : "Такого пакета в AUR нет")
                            : (root.title !== "" ? root.name + " — " : "") + (root.info.summary || "")
                        size: 15
                        color: Theme.inkSoft
                        width: column.width - 92
                        wrapMode: Text.Wrap
                    }
                }
            }

            // Предупреждение и действия.
            Rectangle {
                visible: root.known
                width: parent.width
                height: actions.implicitHeight + 32
                radius: Theme.radius
                color: Theme.surface
                border.width: root.installedVersion !== "" ? 2 : 1
                border.color: root.installedVersion !== "" ? Theme.green : Theme.line

                Column {
                    id: actions
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
                    spacing: 10
                    SText {
                        width: parent.width
                        wrapMode: Text.Wrap
                        size: 13
                        color: Theme.inkSoft
                        text: root.installedVersion !== ""
                            ? "Установлена версия " + root.installedVersion + (root.hasUpdate ? ", в AUR есть " + root.info.version : "")
                            : "Пакеты AUR пишут сами пользователи Arch, и никто их не проверяет. Он соберётся на этом компьютере по своему PKGBUILD — "
                              + "прочитайте его прежде: откуда берутся исходники и что делается при сборке."
                    }
                    SText {
                        visible: root.info.outOfDate === true
                        width: parent.width
                        wrapMode: Text.Wrap
                        size: 13
                        color: Theme.terracotta
                        text: "Пакет отмечен устаревшим: сборка может не получиться."
                    }

                    // Идёт сборка.
                    Column {
                        visible: root.working
                        width: parent.width
                        spacing: 8
                        SText {
                            width: parent.width
                            elide: Text.ElideRight
                            size: 13
                            color: Theme.inkSoft
                            text: root.job.text || ""
                        }
                        Rectangle {
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
                            visible: root.job.cancellable === true
                            text: "Отменить"
                            onClicked: Jobs.cancel(root.job.id)
                        }
                    }
                    // Не получилось.
                    Column {
                        visible: root.job.state === "failed"
                        width: parent.width
                        spacing: 8
                        SText {
                            width: parent.width
                            wrapMode: Text.Wrap
                            size: 13
                            color: Theme.terracotta
                            text: root.job.error || ""
                        }
                        Row {
                            spacing: 8
                            SButton {
                                visible: root.job.code === 4
                                primary: true
                                text: "Обновить систему"
                                onClicked: root.openUpdates()
                            }
                            SButton {
                                text: "Понятно"
                                onClicked: Jobs.dismiss(root.job.id)
                            }
                        }
                    }

                    // Удалить?
                    Row {
                        visible: root.confirmRemove && !root.working
                        spacing: 8
                        SText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Удалить " + root.name + "?"
                            weight: 600
                        }
                        SButton {
                            danger: true
                            text: "Удалить"
                            onClicked: {
                                root.confirmRemove = false;
                                Jobs.removeAur(root.name);
                            }
                        }
                        SButton {
                            text: "Отмена"
                            onClicked: root.confirmRemove = false
                        }
                    }
                    Row {
                        visible: !root.working && root.job.state !== "failed" && !root.confirmRemove
                        spacing: 8
                        SButton {
                            visible: root.installedVersion === "" || root.hasUpdate
                            primary: root.reviewed
                            enabled: root.reviewed
                            opacity: enabled ? 1 : 0.5
                            text: root.hasUpdate ? "Собрать новую версию" : "Собрать и установить"
                            onClicked: Jobs.buildAur(root.info, root.hasUpdate ? "update" : "install")
                        }
                        SButton {
                            visible: root.pkgbuild === "" && root.info.name !== undefined
                            text: "Показать PKGBUILD"
                            onClicked: root.showPkgbuild()
                        }
                        SButton {
                            visible: root.installedVersion !== ""
                            text: "Удалить"
                            onClicked: root.confirmRemove = true
                        }
                    }
                    SText {
                        visible: !root.reviewed && (root.installedVersion === "" || root.hasUpdate) && !root.working && !root.confirmRemove && root.info.name !== undefined
                        size: 12
                        color: Theme.inkMuted
                        text: root.pkgbuildError !== "" ? root.pkgbuildError : "Собрать можно, посмотрев PKGBUILD."
                    }
                }
            }

            // PKGBUILD.
            Rectangle {
                visible: root.pkgbuild !== ""
                width: parent.width
                height: Math.min(code.implicitHeight + 24, 520)
                radius: Theme.radius
                color: Theme.paperDeep
                border.width: 1
                border.color: Theme.line
                Flickable {
                    anchors { fill: parent; margins: 12 }
                    contentWidth: code.implicitWidth
                    contentHeight: code.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }
                    TextEdit {
                        id: code
                        readOnly: true
                        selectByMouse: true
                        text: root.pkgbuild
                        font.family: "monospace"
                        font.pixelSize: 12
                        color: Theme.ink
                        selectionColor: Theme.greenSelect
                    }
                }
            }

            Card {
                visible: root.info.name !== undefined
                title: "Сведения"
                Info { label: "Версия"; value: root.info.version || "" }
                Info { label: "Голосов"; value: root.info.votes !== undefined ? String(root.info.votes) : "" }
                Info { label: "Сопровождает"; value: root.info.maintainer || "никто — пакет брошен" }
                Info { label: "Обновлён"; value: root.info.updated || "" }
                Info { label: "Лицензия"; value: root.info.license || "" }
                Info { label: "Зависимости"; value: (root.info.depends || []).join(", ") }
                Info { label: "Сайт"; value: root.info.url || ""; link: true }
            }
        }
    }

    component Info: Item {
        property string label
        property string value
        property bool link: false
        visible: value !== ""
        width: parent ? parent.width : 0
        height: Math.max(40, valueText.implicitHeight + 20)
        SText {
            anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
            text: parent.label
            color: Theme.inkSoft
        }
        SText {
            id: valueText
            anchors { left: parent.left; leftMargin: 160; right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
            text: parent.value
            wrapMode: Text.Wrap
            color: parent.link ? Theme.green : Theme.ink
            MouseArea {
                anchors.fill: parent
                enabled: parent.parent.link
                cursorShape: Qt.PointingHandCursor
                onClicked: Qt.openUrlExternally(parent.text)
            }
        }
    }
}
