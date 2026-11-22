import QtQuick
import Sedmio.Style

// Откуда поставить программу: репозитории Arch или Flathub. Обе карточки
// равны — выбирает человек; здесь только то, чем источники отличаются,
// и что будет, если нажать: сколько качать, что доставится, что программе
// разрешено.
//   source  — строка Catalog.details().sources
//   info    — Preview.arch или Preview.flathub
//   job     — Jobs.forApp() этого источника или {}
Rectangle {
    id: root
    required property var source
    property var info: ({})
    property var job: ({})
    signal install()
    signal remove()
    signal launch()
    signal cancel()
    signal dismiss()
    signal openUpdates()

    readonly property bool arch: source.kind === "arch"
    readonly property bool installed: source.installed === true
    readonly property bool working: job.state === "waiting" || job.state === "running"
    readonly property bool failed: job.state === "failed"

    function size(bytes) {
        if (!bytes || bytes <= 0) return "";
        const mb = bytes / 1048576;
        if (mb < 1) return "меньше 1 МБ";
        if (mb < 1024) return (mb < 10 ? mb.toFixed(1).replace(".", ",") : Math.round(mb)) + " МБ";
        return (mb / 1024).toFixed(1).replace(".", ",") + " ГБ";
    }
    function plural(n, one, few, many) {
        const m10 = n % 10, m100 = n % 100;
        return m10 === 1 && m100 !== 11 ? one : m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14) ? few : many;
    }

    implicitHeight: column.implicitHeight + 32
    radius: Theme.radius
    color: Theme.surface
    border.width: installed ? 2 : 1
    border.color: installed ? Theme.green : Theme.line

    Column {
        id: column
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
        spacing: 8

        Item {
            width: parent.width
            height: 24
            SIcon {
                id: kindIcon
                anchors.verticalCenter: parent.verticalCenter
                name: root.arch ? "package-x-generic" : "application-vnd.flatpak.ref"
                size: 22
            }
            SText {
                anchors { left: kindIcon.right; leftMargin: 10; verticalCenter: parent.verticalCenter }
                text: root.arch ? "Репозитории Arch" : "Flathub"
                size: 16
                weight: 650
            }
            SText {
                visible: root.installed
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                text: "Установлено"
                size: 12
                weight: 650
                color: Theme.green
            }
        }
        SText {
            width: parent.width
            wrapMode: Text.Wrap
            color: Theme.inkSoft
            size: 13
            text: root.arch
                ? "Обычный пакет системы: обновляется вместе с ней, работает без ограничений, места занимает меньше."
                : "Flatpak в песочнице, со своими библиотеками: обновляется отдельно от системы, места занимает больше."
        }
        SText {
            width: parent.width
            wrapMode: Text.Wrap
            size: 13
            color: Theme.inkMuted
            text: {
                const parts = [];
                if (root.installed && root.source.installedVersion)
                    parts.push("Версия " + root.source.installedVersion);
                else if (root.source.version)
                    parts.push("Версия " + root.source.version);
                if (root.arch && root.source.package)
                    parts.push("пакет " + root.source.package + (root.source.repo ? " (" + root.source.repo + ")" : ""));
                return parts.join(" · ");
            }
        }
        SText {
            visible: !root.arch
            width: parent.width
            wrapMode: Text.Wrap
            size: 13
            color: root.source.verified ? Theme.green : Theme.inkMuted
            text: root.source.verified ? "✓ Выпускает сам разработчик" : "Собрано сообществом, разработчик не проверен"
        }

        // Что будет при установке или удалении.
        SText {
            id: costText
            visible: text !== ""
            width: parent.width
            wrapMode: Text.Wrap
            size: 13
            color: Theme.ink
            text: {
                const i = root.info || {};
                if (i.loading && !i.ok) return "Считаю размер…";
                if (root.installed) {
                    if (!root.arch || !i.removes || i.removes.length === 0) return "";
                    return "При удалении уйдут и ненужные больше: " + i.removes.slice(0, 6).join(", ")
                        + (i.removes.length > 6 ? " и ещё " + (i.removes.length - 6) : "");
                }
                if (!i.ok) return "";
                const parts = [];
                if (i.download > 0) parts.push("Скачать " + root.size(i.download));
                else if (root.arch) parts.push("Уже скачан");
                if (i.installed > 0) parts.push("займёт " + root.size(i.installed));
                let text = parts.join(", ");
                if (root.arch && i.extra && i.extra.length > 0)
                    text += " — вместе с " + i.extra.length + " " + root.plural(i.extra.length, "пакетом", "пакетами", "пакетами");
                if (!root.arch && i.runtimes && i.runtimes.length > 0)
                    text += " — вместе со средой " + i.runtimes.join(", ");
                return text;
            }
        }
        SText {
            readonly property string message: root.installed ? (root.info.removeError || "")
                : (root.info.error && !root.info.loading ? root.info.error : "")
            visible: message !== ""
            width: parent.width
            wrapMode: Text.Wrap
            size: 13
            color: Theme.terracotta
            text: message
        }
        SText {
            visible: root.arch && !root.source.available && !root.installed
            width: parent.width
            wrapMode: Text.Wrap
            size: 13
            color: Theme.terracotta
            text: "Сейчас этого пакета нет в подключённых репозиториях."
        }

        // Песочница Flathub: что программе можно вне её.
        Column {
            readonly property var permissions: root.info.permissions || []
            visible: !root.arch && !root.installed && root.info.ok === true
            width: parent.width
            spacing: 4
            topPadding: 2
            SText {
                size: 13
                weight: 600
                color: Theme.inkSoft
                text: parent.permissions.length > 0 ? "Доступ вне песочницы" : "Только своё окно: без доступа к файлам и устройствам"
            }
            Repeater {
                model: parent.permissions
                delegate: Row {
                    required property var modelData
                    spacing: 8
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 6
                        height: 6
                        radius: 3
                        color: parent.modelData.risky ? Theme.terracotta : Theme.inkMuted
                    }
                    SText {
                        width: column.width - 14
                        wrapMode: Text.Wrap
                        size: 13
                        color: parent.modelData.risky ? Theme.terracotta : Theme.ink
                        text: parent.modelData.text
                    }
                }
            }
        }

        Item { width: 1; height: 4 }

        // Идёт работа: что делаем и сколько осталось.
        Column {
            visible: root.working
            width: parent.width
            spacing: 8
            SText {
                width: parent.width
                elide: Text.ElideRight
                text: root.job.text || ""
                size: 13
                color: Theme.inkSoft
            }
            Rectangle {
                id: track
                width: parent.width
                height: 6
                radius: 3
                color: Theme.paperDeep
                readonly property real progress: root.job.state === "running" ? (root.job.progress ?? -1) : -1
                Rectangle {
                    height: parent.height
                    radius: 3
                    color: Theme.green
                    width: track.progress >= 0 ? Math.max(6, parent.width * track.progress) : parent.width * 0.3
                    x: track.progress >= 0 ? 0 : sweep.position * (parent.width - width)
                    Behavior on width { enabled: track.progress >= 0; NumberAnimation { duration: 250 } }
                }
                QtObject {
                    id: sweep
                    property real position: 0
                }
                SequentialAnimation {
                    running: root.working && track.progress < 0
                    loops: Animation.Infinite
                    NumberAnimation { target: sweep; property: "position"; from: 0; to: 1; duration: 900; easing.type: Easing.InOutQuad }
                    NumberAnimation { target: sweep; property: "position"; from: 1; to: 0; duration: 900; easing.type: Easing.InOutQuad }
                }
            }
            SButton {
                visible: root.job.cancellable === true
                text: "Отменить"
                onClicked: root.cancel()
            }
        }

        // Не получилось.
        Column {
            visible: root.failed
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
                    onClicked: root.dismiss()
                }
            }
        }

        Row {
            visible: !root.working && !root.failed
            spacing: 8
            SButton {
                visible: !root.installed && root.source.available
                primary: true
                text: "Установить"
                onClicked: root.install()
            }
            SButton {
                visible: root.installed
                primary: true
                text: "Открыть"
                onClicked: root.launch()
            }
            SButton {
                visible: root.installed && !(root.arch && root.info.removeError)
                text: "Удалить"
                onClicked: root.remove()
            }
        }
    }
}
