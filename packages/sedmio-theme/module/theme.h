#pragma once

#include <QFileSystemWatcher>
#include <QQmlPropertyMap>
#include <QTimer>
#include <QtQml/qqmlregistration.h>

// Тема Sedmio для всех наших программ: import Sedmio.Style, дальше
// Theme.paper, Theme.radius, Theme.animFast...
//
// Значения — из файла темы sedmio/themes/<тема>/theme.json (сначала
// ~/.local/share, потом /usr/share); какая тема — первая строка файла
// sedmio/theme (сначала ~/.config, потом /etc/xdg). Разделы файла
// ("colors", "fonts", ...) только для порядка: ключи из них лежат в Theme
// рядом. Строка "#RRGGBB" или "#AARRGGBB" — цвет.
//
// Под всё подложена тема по умолчанию, вшитая в модуль: файла темы нет,
// он битый или в нём чего-то не хватает — недостающее берётся оттуда, и
// программа не остаётся без цветов. Файлы меняются — тема меняется на
// ходу, без перезапуска.
//
// Ещё три ключа: themeId, themeName, themeDirectory (каталог темы — для
// её собственного QML, пусто у вшитой).
class Theme : public QQmlPropertyMap
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

public:
    explicit Theme(QObject *parent = nullptr);

private:
    void reload();
    void watch(const QStringList &paths);

    QFileSystemWatcher m_watcher;
    QTimer m_reload;
};
