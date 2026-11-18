// Ярлыки на панели задач: убираем программы, которых нет в системе.
//
// По умолчанию в панели Plasma закреплены «Параметры системы», Discover
// (магазин приложений), файловый менеджер и браузер. Discover в Sedmio нет —
// на панели оставался пустой белый значок.
//
// Скрипт выполняется plasmashell один раз для каждого пользователя
// (отметка в ~/.config/plasmashellrc).
//
// readConfig не видит значение по умолчанию из настроек виджета: пока
// пользователь не менял ярлыки, он возвращает пустой список. Тогда
// записываем стандартный набор без отсутствующих программ; если ярлыки
// уже свои — только убираем из них отсутствующие.
var defaults = [
    "applications:systemsettings.desktop",
    "applications:org.kde.discover.desktop",
    "preferred://filemanager",
    "preferred://browser"
];

function installed(launcher) {
    var prefix = "applications:";
    if (launcher.indexOf(prefix) !== 0) {
        return true;
    }
    return applicationExists(launcher.substring(prefix.length));
}

panels().forEach(function (panel) {
    panel.widgets().forEach(function (widget) {
        if (widget.type !== "org.kde.plasma.icontasks" &&
            widget.type !== "org.kde.plasma.taskmanager") {
            return;
        }
        widget.currentConfigGroup = ["General"];
        var launchers = widget.readConfig("launchers", []);
        if (typeof launchers === "string") {
            launchers = launchers.length ? launchers.split(",") : [];
        }
        if (launchers.length === 0) {
            launchers = defaults;
        }
        var kept = launchers.filter(installed);
        widget.writeConfig("launchers", kept);
    });
});
