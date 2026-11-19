pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Какие обои выбраны: ~/.config/sedmio/wallpaper.json ({"image": "/путь"}),
// пишут «Параметры». Пусто, файла нет или он битый — обои Sedmio.
Singleton {
    id: root

    readonly property string dir:
        (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/sedmio"
    property string image: ""
    // Выбор прочитан (или его нет) — можно решать, что показывать.
    property bool loaded: false
    // Обои на экране: картинка загрузилась (или не открылась), или выбраны
    // обои Sedmio. Тогда и убираем заставку входа — без мигания градиентом.
    property bool shown: false

    // Следить можно, только если папка есть (FileView смотрит в неё, чтобы
    // заметить новый файл) — создаём её до того, как дать путь.
    Process {
        running: true
        command: ["mkdir", "-p", root.dir]
        onExited: config.path = root.dir + "/wallpaper.json"
    }

    FileView {
        id: config
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const image = JSON.parse(text()).image;
                root.image = typeof image === "string" ? image : "";
            } catch (e) {
                root.image = "";
            }
            root.loaded = true;
        }
        onLoadFailed: { root.image = ""; root.loaded = true; }
    }
}
