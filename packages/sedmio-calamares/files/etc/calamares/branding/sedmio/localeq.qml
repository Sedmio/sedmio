import QtQuick
import io.calamares.core 1.0
import io.calamares.ui 1.0
import "components"

// Часовой пояс. Язык не выбирается: система всегда на русском.
// config: модуль locale (regionModel, regionalZonesModel,
// currentTimezoneCode, setCurrentLocation, supportedLocales).
SPage {
    id: page

    stage: 2
    contentWidth: 580
    centerVertically: false

    readonly property string tzCode: config.currentTimezoneCode
    readonly property string tzRegion: tzCode.indexOf("/") > 0 ? tzCode.split("/")[0] : ""
    property string shownRegion: ""
    property string search: ""

    // Язык и форматы — ru_RU.UTF-8, если такая локаль есть в образе.
    function forceRussian() {
        const locales = config.supportedLocales
        for (let i = 0; i < locales.length; ++i) {
            if (locales[i].indexOf("ru_RU.UTF-8") === 0) {
                config.currentLanguageCode = locales[i]
                config.currentLCCode = locales[i]
                return
            }
        }
    }

    function showRegion(key) {
        shownRegion = key
        search = ""
        config.regionalZonesModel.region = key
    }

    function onActivate() {
        forceRussian()
        showRegion(tzRegion)
        page.replayAppear()
    }

    Component.onCompleted: {
        forceRussian()
        showRegion(tzRegion)
    }

    PageHeader {
        width: parent.width
        eyebrow: "Часовой пояс"
        title: "Где вы сейчас?"
        subtitle: "Мы определили: " + config.currentTimezoneName + ". Если неверно — выберите город."
    }

    Row {
        width: parent.width
        height: 300
        spacing: 12

        // Регионы — простым списком без рамки
        ListView {
            width: 170
            height: parent.height
            clip: true
            spacing: 2
            model: config.regionModel
            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
                readonly property bool selected: model.key === page.shownRegion

                width: ListView.view.width
                height: 38
                radius: height / 2
                color: selected ? Theme.green
                     : regionMouse.containsMouse ? Theme.paperDeep
                     : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.animFast } }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    width: parent.width - 28
                    text: model.name
                    elide: Text.ElideRight
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontBody
                    font.weight: parent.selected ? Font.DemiBold : Font.Normal
                    color: parent.selected ? Theme.textOnGreen : Theme.ink
                }

                MouseArea {
                    id: regionMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: page.showRegion(model.key)
                }
            }
        }

        // Города выбранного региона
        Card {
            width: parent.width - 170 - 12
            height: parent.height
            spacing: 6

            STextField {
                width: parent.width
                placeholderText: "Найти город"
                text: page.search
                onTextEdited: page.search = text
            }

            ListView {
                width: parent.width
                height: parent.parent.height - 16 - Theme.controlHeight - 6
                clip: true
                model: config.regionalZonesModel
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                    readonly property bool matches: page.search === ""
                        || model.name.toLowerCase().indexOf(page.search.toLowerCase()) >= 0
                    readonly property bool selected: page.shownRegion + "/" + model.key === page.tzCode

                    width: ListView.view.width
                    height: matches ? 40 : 0
                    visible: matches
                    radius: 12
                    color: selected ? Theme.greenWash
                         : zoneMouse.containsMouse ? Theme.paper
                         : "transparent"
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        width: parent.width - 48
                        text: model.name
                        elide: Text.ElideRight
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontBody
                        font.weight: parent.selected ? Font.DemiBold : Font.Normal
                        color: parent.selected ? Theme.green : Theme.ink
                    }

                    Text {
                        visible: parent.selected
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        text: "✓"
                        font.pixelSize: Theme.fontBody
                        font.weight: Font.Bold
                        color: Theme.green
                    }

                    MouseArea {
                        id: zoneMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: config.setCurrentLocation(page.shownRegion, model.key)
                    }
                }
            }
        }
    }
}
