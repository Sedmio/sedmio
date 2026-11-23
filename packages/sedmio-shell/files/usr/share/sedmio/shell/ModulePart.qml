import QtQuick

// Часть модуля (Modules): грузит modules/<module>/<файл части>, пока модуль
// включён. props — что передать части: ставятся при создании (так можно и
// required property) и дальше обновляются, когда меняются.
Loader {
    id: root
    required property string module
    required property string part
    property var props: ({})

    readonly property url partUrl: Modules.on(module) ? Modules.url(module, part) : ""

    function load() {
        if (partUrl.toString() === "") source = "";
        else setSource(partUrl, props);
    }
    property bool ready: false
    Component.onCompleted: { ready = true; load(); }
    onPartUrlChanged: if (ready) load()

    onPropsChanged: {
        if (!item) return;
        for (const key in props)
            if (item[key] !== props[key]) item[key] = props[key];
    }

    onStatusChanged: if (status === Loader.Error) console.warn("Модуль", module + ": часть", part, "не загрузилась");
}
