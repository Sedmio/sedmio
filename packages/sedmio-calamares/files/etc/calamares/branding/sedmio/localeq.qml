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
    contentWidth: 540   // шире обычного под два списка, но не заходит на растение
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

    // «Азия/Бангкок» → «Бангкок, Азия»
    function placeName(name) {
        const parts = (name || "").split("/")
        return parts.length === 2 ? parts[1] + ", " + parts[0] : name
    }

    // Названия регионов, которые не влезают в колонку
    function regionName(key, name) {
        return key === "Arctic" ? "Арктика" : name
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
        // Без «мы определили»: если сети не было, это просто запасной вариант
        subtitle: "Сейчас выбрано: " + page.placeName(config.currentTimezoneName)
                  + ". Если неверно — выберите свой город."
    }

    Row {
        width: parent.width
        height: 300
        spacing: 12

        // Регионы — простым списком без рамки; у краёв список
        // растворяется в фоне, пока есть что прокручивать
        Item {
            width: 170
            height: parent.height

            ListView {
                id: regions
                anchors.fill: parent
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
                         : Qt.alpha(Theme.paperDeep, 0)
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 16
                        width: parent.width - 28
                        text: page.regionName(model.key, model.name)
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

            ScrollFade { view: regions; atTop: true }
            ScrollFade { view: regions }
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

            Item {
                width: parent.width
                height: parent.parent.height - 16 - Theme.controlHeight - 6

                ListView {
                    id: cities
                    anchors.fill: parent
                    clip: true
                    model: config.regionalZonesModel
                    boundsBehavior: Flickable.StopAtBounds
                    // Все города региона создаются сразу (их до сотни), чтобы
                    // выбранный мог сам прокрутить список к себе
                    cacheBuffer: 6000

                    delegate: Rectangle {
                        readonly property bool matches: page.search === ""
                            || model.name.toLowerCase().indexOf(page.search.toLowerCase()) >= 0
                        readonly property bool selected: page.shownRegion + "/" + model.key === page.tzCode

                        Component.onCompleted: if (selected) Qt.callLater(cities.positionViewAtIndex, index, ListView.Center)

                        width: ListView.view.width
                        height: matches ? 40 : 0
                        visible: matches
                        radius: 12
                        color: selected ? Theme.greenWash
                             : zoneMouse.containsMouse ? Theme.paper
                             : Qt.alpha(Theme.paper, 0)
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

                ScrollFade { view: cities; atTop: true; tint: Theme.surface }
                ScrollFade { view: cities; tint: Theme.surface }
            }
        }
    }
}
