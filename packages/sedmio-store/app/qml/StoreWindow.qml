import QtQuick
import QtQuick.Controls
import Sedmio.Store
import Sedmio.Style

// Окно «Программ»: слева — главная, установленное и разделы, сверху —
// поиск, справа — страница. Страницы — стопкой: «Назад» возвращает к
// прежней вместе с прокруткой.
ApplicationWindow {
    id: win
    width: 1120
    height: 760
    minimumWidth: 760
    minimumHeight: 480
    visible: true
    color: Theme.paper
    title: "Программы"

    // Что выбрано слева: "home" | "installed" | ключ раздела.
    property string section: "home"

    // id — ключ каталога, а также (из оболочки): "aur:<пакет>",
    // "search:<текст>" — поиск, "desktop:<id .desktop>" — карточка
    // программы из меню (для «Удалить»), "appimage:<id>", путь или
    // file:// к файлу AppImage (открыли из файлов, перетащили).
    function openApp(id) {
        if (id.startsWith("file://"))
            id = decodeURIComponent(id.slice(7));
        if (id.startsWith("/")) {
            stack.push(appImageAddPage, { file: id });
            return;
        }
        if (id === "appimage-add") {
            stack.push(appImageAddPage);
            return;
        }
        if (id.startsWith("appimage:")) {
            stack.push(appImagePage, { appId: id.slice(9) });
            return;
        }
        if (id.startsWith("search:")) {
            search.text = id.slice(7);
            win.runSearch(search.text);
            return;
        }
        if (id.startsWith("desktop:")) {
            const appImage = AppImages.byDesktop(id.slice(8));
            if (appImage !== "") {
                openApp("appimage:" + appImage);
                return;
            }
            const found = Catalog.resolveDesktop(id.slice(8));
            if (found.key)
                openApp(found.key);
            else if (found.package && found.foreign)
                stack.push(aurPage, { name: found.package, title: found.name, iconName: found.icon });
            else if (found.package)
                openApp("pkg:" + found.package);
            return;
        }
        if (id.startsWith("aur:"))
            stack.push(aurPage, { name: id.slice(4) });
        else
            stack.push(appPage, { appId: id });
    }
    function openSection(key, title) {
        section = key;
        search.text = "";
        stack.clear(StackView.Immediate);
        if (key === "home")
            stack.push(homePage, {}, StackView.Immediate);
        else if (key === "installed")
            stack.push(installedPage, {}, StackView.Immediate);
        else if (key === "updates")
            stack.push(updatesPage, {}, StackView.Immediate);
        else
            stack.push(categoryPage, { key: key, title: title }, StackView.Immediate);
    }
    function back() {
        if (stack.depth > 1)
            stack.pop();
    }
    // Запрос поиска: страница результатов одна — меняем её запрос.
    function runSearch(text) {
        const query = text.trim();
        const top = stack.currentItem;
        const onSearch = top && top.isSearch === true;
        if (query === "") {
            if (onSearch)
                stack.pop();
            return;
        }
        if (onSearch)
            top.query = query;
        else
            stack.push(searchPage, { query: query });
    }

    Connections {
        target: StoreHost
        function onOpenApp(id) { win.openApp(id); }
    }
    // sedmio-store <id> — карточка, как только каталог готов.
    Connections {
        target: Catalog
        function onReadyChanged() {
            // Число обновлений слева — сразу, не дожидаясь страницы.
            if (Catalog.ready) {
                Catalog.checkUpdates();
                Aur.checkUpdates();
                AppImages.checkUpdates(false);
            }
            const id = StoreHost.takeStartApp();
            if (id !== "")
                win.openApp(id);
        }
    }

    Shortcut { sequences: [StandardKey.Close, StandardKey.Quit]; onActivated: win.close() }
    Shortcut { sequences: [StandardKey.Find, "Ctrl+K"]; onActivated: search.forceActiveFocus() }
    Shortcut { sequences: [StandardKey.Back, "Alt+Left", "Backspace"]; enabled: !search.activeFocus; onActivated: win.back() }
    Shortcut {
        sequence: "Escape"
        onActivated: {
            if (search.text !== "") search.text = "";
            else win.back();
        }
    }

    Rectangle {
        id: sidebar
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
        width: 250
        color: Theme.paperDeep

        Flickable {
            anchors { left: parent.left; right: parent.right; top: parent.top; bottom: jobsStrip.top }
            contentHeight: nav.height + 24
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: nav
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10; topMargin: 16 }
                spacing: 2

                SText {
                    text: "Программы"
                    size: 20
                    weight: 650
                    leftPadding: 10
                    bottomPadding: 12
                }
                NavItem {
                    icon: "go-home"
                    text: "Главная"
                    current: win.section === "home"
                    onClicked: win.openSection("home")
                }
                NavItem {
                    icon: "checkmark"
                    text: "Установленные"
                    current: win.section === "installed"
                    onClicked: win.openSection("installed")
                }
                NavItem {
                    icon: "system-software-update"
                    text: "Обновления"
                    badge: Catalog.updates.length + Aur.installed.filter(p => p.update !== "").length
                        + AppImages.list.filter(a => a.update !== "").length
                    current: win.section === "updates"
                    onClicked: win.openSection("updates")
                }
                SText {
                    text: "Разделы"
                    size: 12
                    weight: 600
                    color: Theme.inkMuted
                    leftPadding: 10
                    topPadding: 16
                    bottomPadding: 6
                }
                Repeater {
                    model: Catalog.categories
                    delegate: NavItem {
                        required property var modelData
                        icon: modelData.icon
                        text: modelData.title
                        current: win.section === modelData.key
                        onClicked: win.openSection(modelData.key, modelData.title)
                    }
                }
            }
        }
    }

    // Внизу слева — что ставится сейчас (видно с любой страницы).
    Column {
        id: jobsStrip
        parent: sidebar
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 10 }
        spacing: 6
        readonly property var active: Jobs.list.filter(j => j.state === "running" || j.state === "waiting")
        Repeater {
            model: jobsStrip.active
            delegate: Rectangle {
                required property var modelData
                width: jobsStrip.width
                height: 54
                radius: 10
                color: Theme.surface
                border.width: 1
                border.color: Theme.line
                AppIcon {
                    id: jobIcon
                    anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                    source: parent.modelData.icon || ""
                    size: 28
                }
                Column {
                    anchors { left: jobIcon.right; leftMargin: 10; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    spacing: 5
                    SText {
                        width: parent.width
                        elide: Text.ElideRight
                        size: 12
                        weight: 600
                        text: parent.parent.modelData.name
                    }
                    Rectangle {
                        width: parent.width
                        height: 4
                        radius: 2
                        color: Theme.paperDeep
                        Rectangle {
                            readonly property real p: parent.parent.parent.modelData.progress
                            width: p >= 0 ? parent.width * p : parent.width * 0.15
                            height: parent.height
                            radius: 2
                            color: Theme.green
                        }
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (!parent.modelData.appId.startsWith("@")) win.openApp(parent.modelData.appId)
                }
            }
        }
    }

    // Верхняя полоса: «Назад» и поиск.
    Item {
        id: topBar
        anchors { left: sidebar.right; right: parent.right; top: parent.top }
        height: 64

        Rectangle {
            id: backButton
            anchors { left: parent.left; leftMargin: 20; verticalCenter: parent.verticalCenter }
            width: 36
            height: 36
            radius: 10
            visible: stack.depth > 1
            color: backArea.containsMouse ? Theme.paperDeep : "transparent"
            SIcon {
                anchors.centerIn: parent
                name: "go-previous"
                size: 22
            }
            MouseArea {
                id: backArea
                anchors.fill: parent
                hoverEnabled: true
                onClicked: win.back()
            }
        }

        SField {
            id: search
            anchors.centerIn: parent
            width: Math.min(560, parent.width - 160)
            height: 40
            leftPadding: 40
            placeholderText: "Найти программу"
            onTextChanged: searchDelay.restart()
            Keys.onEscapePressed: text = ""
            Keys.onDownPressed: stack.currentItem && stack.currentItem.forceActiveFocus()
            SIcon {
                anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                name: "search"
                size: 18
            }
            Component.onCompleted: forceActiveFocus()
        }
        Timer {
            id: searchDelay
            interval: 120
            onTriggered: win.runSearch(search.text)
        }
    }

    StackView {
        id: stack
        anchors { left: sidebar.right; right: parent.right; top: topBar.bottom; bottom: parent.bottom }
        clip: true
        initialItem: homePage

        pushEnter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.animFast } }
        pushExit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Theme.animFast } }
        popEnter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.animFast } }
        popExit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Theme.animFast } }
    }

    // Перетащили файл AppImage в окно — добавить.
    DropArea {
        id: drop
        anchors.fill: stack
        readonly property string appImage: {
            for (const url of drop.urls ?? []) {
                const text = url.toString();
                if (/\.appimage$/i.test(text) && text.startsWith("file://"))
                    return text;
            }
            return "";
        }
        property var urls: []
        onEntered: event => {
            drop.urls = event.urls;
            if (drop.appImage === "") event.accepted = false;
        }
        onExited: drop.urls = []
        onDropped: event => {
            const url = drop.appImage;
            drop.urls = [];
            if (url !== "") {
                event.acceptProposedAction();
                win.openApp(url);
            }
        }
        Rectangle {
            anchors { fill: parent; margins: 16 }
            visible: drop.containsDrag && drop.appImage !== ""
            radius: Theme.radius
            color: Qt.alpha(Theme.paper, 0.9)
            border.width: 2
            border.color: Theme.green
            SText {
                anchors.centerIn: parent
                text: "Отпустите, чтобы добавить AppImage"
                size: 18
                weight: 650
                color: Theme.green
            }
        }
    }

    // Каталог ещё грузится.
    Rectangle {
        anchors.fill: stack
        visible: !Catalog.ready
        color: Theme.paper
        Column {
            anchors.centerIn: parent
            spacing: 12
            BusyIndicator {
                anchors.horizontalCenter: parent.horizontalCenter
                running: parent.parent.visible
            }
            SText {
                text: "Загружаю каталог…"
                color: Theme.inkMuted
            }
        }
    }

    Component {
        id: homePage
        HomePage {
            onOpen: id => win.openApp(id)
        }
    }
    Component {
        id: installedPage
        ListPage {
            title: "Установленные"
            subtitle: "Из репозиториев Arch, с Flathub, из AUR и AppImage"
            emptyText: "Из магазина пока ничего не установлено"
            apps: Catalog.ready && Catalog.revision >= 0 ? Catalog.installedApps() : []
            emptyVisible: apps.length === 0 && !Aur.installed.some(p => p.inAur) && AppImages.list.length === 0
            onOpen: id => win.openApp(id)
            footer: Component {
                Column {
                    AurInstalled {
                        width: parent.width
                        onOpen: name => win.openApp("aur:" + name)
                    }
                    AppImageInstalled {
                        width: parent.width
                        onOpen: id => win.openApp("appimage:" + id)
                        onAdd: win.openApp("appimage-add")
                    }
                }
            }
        }
    }
    Component {
        id: categoryPage
        ListPage {
            property string key
            apps: Catalog.ready && Catalog.revision >= 0 ? Catalog.category(key) : []
            onOpen: id => win.openApp(id)
        }
    }
    Component {
        id: searchPage
        ListPage {
            id: searchList
            readonly property bool isSearch: true
            property string query
            title: "Поиск: " + query
            emptyText: "Ничего не нашлось"
            apps: Catalog.ready && Catalog.revision >= 0 ? Catalog.search(query) : []
            onOpen: id => win.openApp(id)
            footer: Component {
                Column {
                    PackageResults {
                        width: parent.width
                        query: searchList.query
                        onOpen: id => win.openApp(id)
                    }
                    AurResults {
                        width: parent.width
                        query: searchList.query
                        onOpen: name => win.openApp("aur:" + name)
                    }
                }
            }
        }
    }
    Component {
        id: appPage
        AppPage {
            onOpenUpdates: StoreHost.openSystemUpdates()
        }
    }
    Component {
        id: aurPage
        AurPage {
            onOpenUpdates: StoreHost.openSystemUpdates()
            onReview: (targets, update) => stack.push(aurReviewPage, { targets: targets, update: update })
        }
    }
    Component {
        id: aurReviewPage
        AurReviewPage {
            onDone: stack.pop()
        }
    }
    Component {
        id: appImagePage
        AppImagePage {
            onClosed: stack.pop()
        }
    }
    Component {
        id: appImageAddPage
        AppImageAddPage {
            onAdded: id => stack.replace(appImagePage, { appId: id })
            onOpenExisting: id => stack.replace(appImagePage, { appId: id })
        }
    }
    Component {
        id: updatesPage
        UpdatesPage {
            onOpen: id => win.openApp(id)
            onReviewAur: names => stack.push(aurReviewPage, { targets: names, update: true })
        }
    }
}
