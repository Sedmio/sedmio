#pragma once

#include <QColor>
#include <QFileSystemWatcher>
#include <QObject>
#include <QTimer>
#include <QVariant>
#include <QVariantMap>

namespace Sedmio
{

// Тема Sedmio: значения из файла выбранной темы поверх вшитой темы по
// умолчанию. Один на процесс; общий для QML-модуля Sedmio.Style и рамок
// окон KWin.
//
// Файл темы — sedmio/themes/<тема>/theme.json (сначала ~/.local/share,
// потом /usr/share); какая тема — первая строка файла sedmio/theme (сначала
// ~/.config, потом /etc/xdg), иначе «sedmio». Разделы файла ("colors",
// "fonts", ...) только для порядка: ключи из них лежат рядом. Строка
// "#RRGGBB" или "#AARRGGBB" — цвет.
//
// Вшитая тема подложена под любую: файла нет, он битый, в нём чего-то нет
// или значение не того типа — берётся вшитое. Файлы отслеживаются: тема
// поменялась — changed().
//
// Ещё ключи: themeId, themeName, themeDirectory (каталог темы — для
// её собственных файлов; пусто у вшитой), accentFromWallpaper (акцентные
// цвета перекрашены в цвет обоев, accent.h).
class ThemeData : public QObject
{
    Q_OBJECT

public:
    static ThemeData *instance();

    QVariantMap values() const { return m_values; }
    QVariant value(const QString &key) const { return m_values.value(key); }
    QColor color(const QString &key) const { return m_values.value(key).value<QColor>(); }
    qreal number(const QString &key) const { return m_values.value(key).toReal(); }
    QString string(const QString &key) const { return m_values.value(key).toString(); }

Q_SIGNALS:
    void changed();

private:
    ThemeData();
    void reload();
    void watch(const QStringList &paths);

    QVariantMap m_values;
    QFileSystemWatcher m_watcher;
    QTimer m_reload;
};

} // namespace Sedmio
