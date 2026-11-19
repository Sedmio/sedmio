import QtQuick
import Sedmio.Preferences
import Sedmio.Style

// «Тема»: установленные темы Sedmio карточками — маленький рабочий стол в
// цветах темы. Щелчок — тема сразу везде: оболочка, наши программы, рамки
// окон, чужие программы.
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

                    // Рабочий стол темы: обои, полоса оболочки, окно.
                    Rectangle {
                        id: desk
                        anchors.fill: parent
                        anchors.margins: parent.border.width
                        radius: Theme.radius - 2
                        clip: true
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: tile.c.wallpaperTop }
                            GradientStop { position: 1.0; color: tile.c.wallpaperBottom }
                        }

                        Rectangle {
                            id: bar
                            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                            width: desk.width * 0.07
                            color: tile.c.paper
                            Column {
                                anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: bar.width * 0.4 }
                                spacing: bar.width * 0.3
                                Repeater {
                                    model: 3
                                    Rectangle {
                                        required property int index
                                        width: bar.width * 0.5
                                        height: width
                                        radius: width * 0.25
                                        color: index === 0 ? tile.c.green : tile.c.inkMuted
                                        opacity: index === 0 ? 1 : 0.45
                                    }
                                }
                            }
                        }

                        Rectangle {
                            id: window
                            x: desk.width * 0.2
                            y: desk.height * 0.16
                            width: desk.width * 0.68
                            height: desk.height * 0.68
                            radius: desk.height * 0.05
                            color: tile.c.surface
                            border.width: 1
                            border.color: tile.c.line
                            clip: true

                            Rectangle {
                                width: parent.width
                                height: parent.height * 0.17
                                color: tile.c.windowTitle
                                radius: parent.radius
                                Rectangle {
                                    anchors { right: parent.right; rightMargin: parent.height * 0.4; verticalCenter: parent.verticalCenter }
                                    width: parent.height * 0.35
                                    height: width
                                    radius: width / 2
                                    color: tile.c.terracotta
                                }
                            }

                            Column {
                                x: parent.width * 0.08
                                y: parent.height * 0.3
                                spacing: parent.height * 0.08
                                Rectangle { width: window.width * 0.55; height: window.height * 0.07; radius: height / 2; color: tile.c.ink }
                                Rectangle { width: window.width * 0.4; height: window.height * 0.05; radius: height / 2; color: tile.c.inkMuted }
                                Rectangle {
                                    width: window.width * 0.3
                                    height: window.height * 0.16
                                    radius: height / 2
                                    color: tile.c.green
                                }
                            }
                        }
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
}
