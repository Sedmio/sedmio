import QtQuick
import QtQuick.Layouts
import Sedmio.Files
import Sedmio.Style

// Окно «Свойства»: что это, где лежит, сколько весит (папки считаются
// на ходу), даты, чем открывается и кому что можно. Для нескольких
// выбранных — сколько их и сколько весят вместе.
Window {
    id: win
    required property var urls

    Properties {
        id: props
        urls: win.urls
    }

    readonly property bool single: props.count === 1

    title: "Свойства «" + (single ? props.name : Format.items(props.count)) + "»"
    flags: Qt.Dialog
    color: Theme.paper

    readonly property int contentHeight: column.implicitHeight + 48
    width: 480
    height: contentHeight
    minimumWidth: 480
    maximumWidth: 480
    minimumHeight: contentHeight
    maximumHeight: contentHeight

    Shortcut { sequences: ["Escape", "Ctrl+W"]; onActivated: win.close() }

    Menu { id: menu }

    // ---- Подписи

    function sizeText() {
        if (props.counting && props.size === 0) return "Считаем…";
        let text = FileOps.formatSize(props.size);
        if (props.size >= 1024) text += " (" + Format.number(props.size) + " " + Format.plural(props.size, "байт", "байта", "байт") + ")";
        return text;
    }
    function contentsText() {
        const parts = [];
        if (props.files > 0 || props.folders === 0)
            parts.push(Format.number(props.files) + " " + Format.plural(props.files, "файл", "файла", "файлов"));
        if (props.folders > 0)
            parts.push(Format.number(props.folders) + " " + Format.plural(props.folders, "папка", "папки", "папок"));
        return parts.join(", ");
    }

    // Уровень доступа: 0 — нет, 1 — читать, 2 — читать и менять.
    function level(who) {
        const bits = (props.mode >> ((2 - who) * 3)) & 7;
        return (bits & 4) ? ((bits & 2) ? 2 : 1) : 0;
    }
    readonly property var levelNames: props.isDir
        ? ["Нет доступа", "Только просмотр", "Просмотр и изменение"]
        : ["Нет доступа", "Только чтение", "Чтение и запись"]

    function chooseLevel(who, button) {
        menu.items = [0, 1, 2].map(l => ({
            text: win.levelNames[l],
            checked: win.level(who) === l,
            action: () => props.setAccess(who, l)
        }));
        menu.openAt(button, 0, button.height + 4);
    }

    function chooseApplication(button) {
        const apps = FileOps.applications(props.mimeType);
        menu.items = apps.map(app => ({
            text: app.name,
            icon: app.icon,
            checked: app.id === props.application.id,
            action: () => props.setApplication(app.id)
        }));
        if (menu.items.length > 0) menu.openAt(button, 0, button.height + 4);
    }

    ColumnLayout {
        id: column
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 24 }
        spacing: 16

        // Значок, имя, тип
        RowLayout {
            Layout.fillWidth: true
            spacing: 16

            FileIcon {
                Layout.preferredWidth: 72
                Layout.preferredHeight: 72
                size: 72
                iconName: props.iconName
                url: win.single ? win.urls[0] : ""
                mimeType: props.mimeType
                canPreview: props.canPreview
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                TextEdit {
                    Layout.fillWidth: true
                    readOnly: true
                    selectByMouse: true
                    wrapMode: TextEdit.Wrap
                    font.family: Theme.fontFamily
                    font.pixelSize: 18
                    font.weight: 600
                    color: Theme.ink
                    selectionColor: Theme.greenSelect
                    selectedTextColor: Theme.ink
                    text: win.single ? props.name : Format.items(props.count)
                }
                SText {
                    Layout.fillWidth: true
                    color: Theme.inkMuted
                    elide: Text.ElideRight
                    text: props.typeName !== "" ? props.typeName
                        : win.single ? "" : "Разные типы"
                    visible: text !== ""
                }
            }
        }

        // Где, сколько, когда
        Card {
            InfoRow {
                label: "Где"
                value: props.parentUrl.toString() !== "" ? FileOps.prettyPath(props.parentUrl) : ""
            }
            InfoRow { label: "Ссылка на"; value: props.linkTarget }
            InfoRow { label: "Размер"; value: props.ready ? win.sizeText() : "" }
            InfoRow {
                label: "Внутри"
                value: props.ready && (props.isDir || !win.single) && !(props.counting && props.files === 0)
                       ? win.contentsText() + (props.counting ? " · считаем…" : "") : ""
            }
            InfoRow { label: "Изменён"; value: Format.fullDate(props.modified) }
            InfoRow { label: "Создан"; value: Format.fullDate(props.created) }
            InfoRow { label: "Открывали"; value: Format.fullDate(props.accessed) }
        }

        // Место на диске
        Card {
            visible: props.diskSize > 0
            InfoRow {
                label: "Диск"
                value: "свободно " + FileOps.formatSize(props.diskFree) + " из " + FileOps.formatSize(props.diskSize)
            }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 6
                radius: 3
                color: Theme.paperDeep
                Rectangle {
                    readonly property real used: props.diskSize > 0 ? 1 - props.diskFree / props.diskSize : 0
                    width: parent.width * used
                    height: parent.height
                    radius: 3
                    color: used > 0.9 ? Theme.terracotta : Theme.leaf
                }
            }
        }

        // Чем открывается
        Card {
            visible: props.ready && !props.isDir && props.mimeType !== ""
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                SText {
                    Layout.preferredWidth: 110
                    color: Theme.inkMuted
                    text: "Открывать"
                }
                SIcon {
                    visible: !!props.application.icon
                    name: props.application.icon ?? ""
                    size: 20
                }
                SText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: props.application.name ?? "Не выбрано"
                    color: props.application.name ? Theme.ink : Theme.inkMuted
                }
                SButton {
                    id: appButton
                    text: "Изменить"
                    onClicked: win.chooseApplication(appButton)
                }
            }
        }

        // Права
        Card {
            visible: win.single && props.isLocal && props.ready
            SText {
                Layout.fillWidth: true
                size: Theme.fontSmall
                weight: 600
                color: Theme.inkMuted
                text: props.canChangeMode ? "Доступ" : "Доступ (менять может только владелец)"
            }
            Repeater {
                model: [
                    { who: 0, name: "Владелец", hint: props.owner },
                    { who: 1, name: "Группа", hint: props.group },
                    { who: 2, name: "Остальные", hint: "" }
                ]
                delegate: RowLayout {
                    id: accessRow
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 10
                    SText {
                        Layout.preferredWidth: 110
                        color: Theme.inkMuted
                        text: accessRow.modelData.name
                    }
                    SText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        size: Theme.fontSmall
                        color: Theme.inkMuted
                        text: accessRow.modelData.hint
                    }
                    Chooser {
                        id: chooser
                        text: win.levelNames[win.level(accessRow.modelData.who)]
                        enabled: props.canChangeMode
                        onClicked: win.chooseLevel(accessRow.modelData.who, chooser)
                    }
                }
            }
            Check {
                visible: !props.isDir
                enabled: props.canChangeMode
                checked: (props.mode & 73) !== 0
                text: "Запускать как программу"
                onToggled: props.setExecutable(!checked)
            }
        }

        SText {
            Layout.fillWidth: true
            visible: props.error !== ""
            wrapMode: Text.Wrap
            color: Theme.terracotta
            text: props.error
        }

        RowLayout {
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }
            SButton {
                text: "Закрыть"
                primary: true
                onClicked: win.close()
            }
        }
    }

    // ---- Части окна

    component Card: Rectangle {
        default property alias content: cardColumn.data
        Layout.fillWidth: true
        implicitHeight: cardColumn.implicitHeight + 24
        radius: 12
        color: Theme.surface
        border.width: 1
        border.color: Theme.line

        ColumnLayout {
            id: cardColumn
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
            spacing: 8
        }
    }

    // Строка «подпись — значение»; без значения не видна.
    component InfoRow: RowLayout {
        id: infoRow
        property string label
        property string value
        Layout.fillWidth: true
        visible: value !== ""
        spacing: 10
        SText {
            Layout.preferredWidth: 110
            Layout.alignment: Qt.AlignTop
            color: Theme.inkMuted
            text: infoRow.label
        }
        TextEdit {
            Layout.fillWidth: true
            readOnly: true
            selectByMouse: true
            wrapMode: TextEdit.WrapAnywhere
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontBody
            color: Theme.ink
            selectionColor: Theme.greenSelect
            selectedTextColor: Theme.ink
            text: infoRow.value
        }
    }

    // Кнопка выбора из списка: текст и стрелка.
    component Chooser: Rectangle {
        id: chooserRoot
        property string text
        signal clicked()
        implicitWidth: 200
        implicitHeight: 32
        radius: 9
        opacity: enabled ? 1 : 0.6
        color: chooserArea.containsMouse && enabled ? Theme.paper : Theme.surface
        border.width: 1
        border.color: Theme.line
        SText {
            anchors { left: parent.left; leftMargin: 10; right: arrow.left; rightMargin: 6; verticalCenter: parent.verticalCenter }
            elide: Text.ElideRight
            size: 13
            text: chooserRoot.text
        }
        SIcon {
            id: arrow
            anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
            name: "arrow-down"
            size: 12
            visible: chooserRoot.enabled
        }
        MouseArea {
            id: chooserArea
            anchors.fill: parent
            hoverEnabled: true
            enabled: chooserRoot.enabled
            onClicked: chooserRoot.clicked()
        }
    }

    component Check: Item {
        id: check
        property bool checked: false
        property string text
        signal toggled()
        Layout.fillWidth: true
        implicitHeight: checkRow.implicitHeight
        opacity: enabled ? 1 : 0.6
        Row {
            id: checkRow
            spacing: 8
            Rectangle {
                width: 18
                height: 18
                radius: 5
                anchors.verticalCenter: parent.verticalCenter
                color: check.checked ? Theme.green : Theme.surface
                border.width: check.checked ? 0 : 1
                border.color: Theme.lineStrong
                SText {
                    anchors.centerIn: parent
                    visible: check.checked
                    size: 13
                    weight: 700
                    color: Theme.textOnGreen
                    text: "✓"
                }
            }
            SText {
                anchors.verticalCenter: parent.verticalCenter
                text: check.text
            }
        }
        MouseArea {
            anchors.fill: parent
            enabled: check.enabled
            onClicked: check.toggled()
        }
    }
}
