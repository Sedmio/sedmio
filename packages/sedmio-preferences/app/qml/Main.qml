import QtQuick
import QtQuick.Controls
import Sedmio.Preferences
import Sedmio.Style

// Окно «Параметров»: разделы слева, раздел справа. Внизу слева — параметры
// KDE для всего, чего у нас пока нет.
ApplicationWindow {
    id: win
    width: 980
    height: 660
    minimumWidth: 780
    minimumHeight: 480
    visible: true
    color: Theme.paper
    title: currentTitle + " — Параметры"

    readonly property var pages: [
        { id: "display", title: "Экран", icon: "preferences-desktop-display" },
        { id: "theme", title: "Тема", icon: "preferences-desktop-theme-global" },
        { id: "wallpaper", title: "Обои", icon: "preferences-desktop-wallpaper" },
        { id: "mouse", title: "Мышь и тачпад", icon: "preferences-desktop-mouse" },
        { id: "keyboard", title: "Клавиатура", icon: "preferences-desktop-keyboard" },
        { id: "sound", title: "Звук", icon: "preferences-desktop-sound" },
        { id: "network", title: "Сеть", icon: "preferences-system-network" },
        { id: "bluetooth", title: "Bluetooth", icon: "preferences-system-bluetooth" },
        { id: "power", title: "Питание", icon: "preferences-system-power-management" },
        { id: "defaults", title: "Программы по умолчанию", icon: "preferences-desktop-default-applications" },
        { id: "autostart", title: "Автозапуск", icon: "system-run" },
        { id: "account", title: "Учётная запись", icon: "system-users" },
        { id: "datetime", title: "Дата и время", icon: "preferences-system-time" },
        { id: "about", title: "О системе", icon: "help-about" }
    ]
    readonly property string currentTitle: {
        for (const page of pages)
            if (page.id === App.page) return page.title;
        return "";
    }

    // Экраны — на всё окно, не на страницу: отсчёт «вернуть через 15 с»
    // идёт, даже если ушли в другой раздел.
    Displays { id: screens }

    Shortcut { sequences: [StandardKey.Close, StandardKey.Quit]; onActivated: win.close() }

    Rectangle {
        id: sidebar
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
        width: 262
        color: Theme.paperDeep

        Column {
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10; topMargin: 16 }
            spacing: 2

            SText {
                text: "Параметры"
                size: 20
                weight: 650
                leftPadding: 10
                bottomPadding: 12
            }

            Repeater {
                model: win.pages
                delegate: Rectangle {
                    required property var modelData
                    readonly property bool current: App.page === modelData.id
                    width: parent.width
                    height: 36
                    radius: 9
                    color: current ? Theme.greenWash : navArea.containsMouse ? Theme.paper : "transparent"
                    SIcon {
                        id: navIcon
                        anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                        name: parent.modelData.icon
                        size: 22
                    }
                    SText {
                        anchors { left: navIcon.right; leftMargin: 10; right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                        text: parent.modelData.title
                        weight: parent.current ? 600 : 400
                        elide: Text.ElideRight
                    }
                    MouseArea {
                        id: navArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: App.page = parent.modelData.id
                    }
                }
            }
        }

        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 10 }
            height: 36
            radius: 9
            color: kdeArea.containsMouse ? Theme.paper : "transparent"
            SIcon {
                id: kdeIcon
                anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                name: "systemsettings"
                size: 22
            }
            SText {
                anchors { left: kdeIcon.right; leftMargin: 10; verticalCenter: parent.verticalCenter }
                text: "Ещё в параметрах KDE"
                color: Theme.inkSoft
            }
            MouseArea {
                id: kdeArea
                anchors.fill: parent
                hoverEnabled: true
                onClicked: App.openKde()
            }
        }
    }

    Loader {
        id: page
        anchors { left: sidebar.right; right: parent.right; top: parent.top; bottom: parent.bottom }
        sourceComponent: App.page === "theme" ? themePage
                       : App.page === "wallpaper" ? wallpaperPage
                       : App.page === "mouse" ? mousePage
                       : App.page === "keyboard" ? keyboardPage
                       : App.page === "sound" ? soundPage
                       : App.page === "network" ? networkPage
                       : App.page === "bluetooth" ? bluetoothPage
                       : App.page === "power" ? powerPage
                       : App.page === "defaults" ? defaultsPage
                       : App.page === "autostart" ? autostartPage
                       : App.page === "account" ? accountPage
                       : App.page === "datetime" ? dateTimePage
                       : App.page === "about" ? aboutPage
                       : displayPage
    }

    Component { id: displayPage; DisplayPage { displays: screens } }
    Component { id: themePage; ThemePage {} }
    Component { id: wallpaperPage; WallpaperPage {} }
    Component { id: mousePage; MousePage {} }
    Component { id: keyboardPage; KeyboardPage {} }
    Component { id: soundPage; SoundPage {} }
    Component { id: networkPage; NetworkPage {} }
    Component { id: bluetoothPage; BluetoothPage {} }
    Component { id: powerPage; PowerPage {} }
    Component { id: defaultsPage; DefaultsPage {} }
    Component { id: autostartPage; AutostartPage {} }
    Component { id: accountPage; AccountPage {} }
    Component { id: dateTimePage; DateTimePage {} }
    Component { id: aboutPage; AboutPage {} }
}
