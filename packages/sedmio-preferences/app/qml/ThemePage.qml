import QtQuick
import Sedmio.Preferences
import Sedmio.Style

// «Тема»: установленные темы Sedmio карточками — маленький рабочий стол в
// цветах темы. Щелчок — тема сразу везде: оболочка, наши программы, рамки
// окон, чужие программы. Под ними — акцентный цвет из обоев (поверх любой
// темы). Ниже — расположение панелей (макет оболочки):
// тоже карточками, меняется сразу; под ними — ползунки толщины панелей
// выбранного макета (оболочка меняется, пока тянешь).
Page {
    id: root
    title: "Тема"

    Themes { id: themes }

    readonly property int columns: Math.max(2, Math.floor((contentWidth + 14) / 234))
    readonly property real tileWidth: (contentWidth - (columns - 1) * 14) / columns

    SText {
        visible: themes.error !== ""
        width: parent.width
        text: themes.error
        color: Theme.terracotta
        wrapMode: Text.Wrap
    }

    // Цвета действующей темы — для карточек расположения.
    readonly property var currentColors: (themes.themes.find(t => t.id === Theme.themeId) ?? themes.themes[0] ?? {}).colors ?? ({})

    readonly property var layouts: [
        { id: "left", name: "Слева", description: "Одна полоса слева: программы сверху, значки и часы снизу" },
        { id: "dock", name: "Сверху и док", description: "Панель сверху, программы в доке по центру; док прячется, пока окно развёрнуто" },
        { id: "taskbar", name: "Сверху и снизу", description: "Панель сверху, снизу панель задач с подписями окон" },
    ]

    SText {
        text: "Цвета"
        size: 13
        weight: 600
        color: Theme.inkSoft
        leftPadding: 4
    }

    Flow {
        width: parent.width
        spacing: 14

        Repeater {
            model: themes.themes
            delegate: Column {
                id: tile
                required property var modelData
                readonly property var c: modelData.colors
                readonly property bool current: modelData.id === Theme.themeId
                width: root.tileWidth
                spacing: 6

                Rectangle {
                    width: parent.width
                    height: width * 10 / 16
                    radius: Theme.radius
                    color: Theme.paperDeep
                    border.width: tile.current ? 3 : 1
                    border.color: tile.current ? Theme.green : (tileArea.containsMouse ? Theme.lineStrong : Theme.line)

                    // Рабочий стол темы: обои, панели по выбранному макету, окно.
                    DesktopPreview {
                        anchors.fill: parent
                        anchors.margins: parent.border.width
                        radius: Theme.radius - 2
                        layout: themes.layout
                        c: tile.c
                    }

                    MouseArea {
                        id: tileArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: themes.choose(tile.modelData.id)
                    }
                }

                SText {
                    width: parent.width
                    text: tile.modelData.name
                    weight: tile.current ? 600 : 500
                    elide: Text.ElideRight
                }
                SText {
                    visible: text !== ""
                    width: parent.width
                    text: tile.modelData.description
                    size: Theme.fontSmall
                    color: Theme.inkMuted
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
            }
        }
    }

    Card {
        title: "Акцентный цвет"
        Setting {
            label: "Из обоев"
            hint: "Кнопки, выделение и отметки — в цвет картинки рабочего стола"
            last: true
            Row {
                spacing: 14
                // Акцент сейчас — меняется вместе с обоями.
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 22
                    height: 22
                    radius: 11
                    color: Theme.green
                    border.width: 3
                    border.color: Theme.greenWash
                    Behavior on color { ColorAnimation { duration: Theme.animNormal } }
                }
                SSwitch {
                    anchors.verticalCenter: parent.verticalCenter
                    checked: Theme.accentFromWallpaper === true
                    onToggled: themes.setAccentFromWallpaper(!checked)
                }
            }
        }
    }

    SText {
        topPadding: 8
        text: "Расположение панелей"
        size: 13
        weight: 600
        color: Theme.inkSoft
        leftPadding: 4
    }

    Flow {
        width: parent.width
        spacing: 14

        Repeater {
            model: root.layouts
            delegate: Column {
                id: card
                required property var modelData
                readonly property bool current: modelData.id === themes.layout
                width: root.tileWidth
                spacing: 6

                Rectangle {
                    width: parent.width
                    height: width * 10 / 16
                    radius: Theme.radius
                    color: Theme.paperDeep
                    border.width: card.current ? 3 : 1
                    border.color: card.current ? Theme.green : (cardArea.containsMouse ? Theme.lineStrong : Theme.line)

                    DesktopPreview {
                        anchors.fill: parent
                        anchors.margins: parent.border.width
                        radius: Theme.radius - 2
                        layout: card.modelData.id
                        c: root.currentColors
                    }

                    MouseArea {
                        id: cardArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: themes.chooseLayout(card.modelData.id)
                    }
                }

                SText {
                    width: parent.width
                    text: card.modelData.name
                    weight: card.current ? 600 : 500
                    elide: Text.ElideRight
                }
                SText {
                    width: parent.width
                    text: card.modelData.description
                    size: Theme.fontSmall
                    color: Theme.inkMuted
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
            }
        }
    }

    // Какие панели есть в макете и как они называются.
    readonly property var panelKeys: ({ left: ["left"], dock: ["top", "dock"], taskbar: ["top", "taskbar"] })
    readonly property var panelNames: ({ left: "Полоса слева", top: "Верхняя панель", dock: "Док", taskbar: "Панель задач" })

    Card {
        title: "Размер панелей"
        Repeater {
            id: panelRows
            // Список ключей меняется только со сменой макета — строки не
            // пересоздаются, пока тянут ползунок.
            model: root.panelKeys[themes.layout] ?? []
            delegate: Setting {
                id: row
                required property string modelData
                required property int index
                readonly property var panel: themes.panels.find(p => p.key === modelData) ?? { value: 0, min: 0, max: 1 }
                label: root.panelNames[modelData]
                last: index === panelRows.count - 1
                SSlider {
                    width: 260
                    maximum: row.panel.max - row.panel.min
                    step: 2
                    value: row.panel.value - row.panel.min
                    onMoved: value => themes.setPanelSize(row.modelData, row.panel.min + Math.round(value / 2) * 2)
                }
            }
        }
    }
}
