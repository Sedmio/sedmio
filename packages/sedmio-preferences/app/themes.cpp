#include "themes.h"

#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QSaveFile>
#include <QStandardPaths>

#include <algorithm>

namespace
{
QStringList themeDirs()
{
    QStringList dirs;
    for (const QString &base : QStandardPaths::standardLocations(QStandardPaths::GenericDataLocation))
        dirs << base + QStringLiteral("/sedmio/themes");
    return dirs;
}

// Ключи из разделов файла — рядом (как в модуле Sedmio.Style).
bool read(const QString &path, QVariantMap *values)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
        return false;
    const QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
    if (!doc.isObject())
        return false;
    const QJsonObject root = doc.object();
    for (auto it = root.begin(); it != root.end(); ++it) {
        if (it.value().isObject()) {
            const QJsonObject section = it.value().toObject();
            for (auto s = section.begin(); s != section.end(); ++s)
                values->insert(s.key(), s.value().toVariant());
        } else {
            values->insert(it.key(), it.value().toVariant());
        }
    }
    return true;
}

const QStringList layouts = {QStringLiteral("left"), QStringLiteral("dock"), QStringLiteral("taskbar")};

QString configDir()
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation) + QStringLiteral("/sedmio");
}

// Как в оболочке: нет файла или неизвестное имя — "left".
QString readLayout()
{
    QFile file(configDir() + QStringLiteral("/layout"));
    if (!file.open(QIODevice::ReadOnly))
        return layouts.constFirst();
    const QString id = QString::fromUtf8(file.readLine(64)).trimmed();
    return layouts.contains(id) ? id : layouts.constFirst();
}

const QStringList previewColors = {
    QStringLiteral("paper"),      QStringLiteral("paperDeep"),  QStringLiteral("surface"),     QStringLiteral("line"),
    QStringLiteral("ink"),        QStringLiteral("inkMuted"),   QStringLiteral("green"),       QStringLiteral("textOnGreen"),
    QStringLiteral("terracotta"), QStringLiteral("windowTitle"), QStringLiteral("wallpaperTop"), QStringLiteral("wallpaperBottom"),
};
} // namespace

Themes::Themes(QObject *parent)
    : QObject(parent)
{
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, this, &Themes::rescan);
    rescan();
    m_layout = readLayout();
}

void Themes::rescan()
{
    // Основа для недостающих цветов — тема sedmio.
    QVariantMap base;
    for (const QString &dir : themeDirs()) {
        if (read(dir + QStringLiteral("/sedmio/theme.json"), &base))
            break;
    }

    QStringList seen;
    QVariantList themes;
    // Сначала свои (~/.local/share), они перекрывают системные.
    for (const QString &dir : themeDirs()) {
        const auto entries = QDir(dir).entryList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name);
        for (const QString &id : entries) {
            if (seen.contains(id))
                continue;
            QVariantMap values;
            if (!read(dir + QLatin1Char('/') + id + QStringLiteral("/theme.json"), &values))
                continue; // нет файла или не JSON — модуль её тоже не возьмёт
            seen << id;

            QVariantMap colors;
            for (const QString &key : previewColors) {
                const QString value = values.value(key, base.value(key)).toString();
                colors.insert(key, value.startsWith(QLatin1Char('#')) ? value : base.value(key).toString());
            }
            const QString name = values.value(QStringLiteral("name")).toString();
            themes << QVariantMap{
                {QStringLiteral("id"), id},
                {QStringLiteral("name"), name.isEmpty() ? id : name},
                {QStringLiteral("description"), values.value(QStringLiteral("description")).toString()},
                {QStringLiteral("user"), dir == themeDirs().constFirst()},
                {QStringLiteral("colors"), colors},
            };
        }
    }
    // Тема по умолчанию — первой, остальные по имени.
    std::sort(themes.begin(), themes.end(), [](const QVariant &a, const QVariant &b) {
        const QVariantMap x = a.toMap(), y = b.toMap();
        const bool xs = x.value(QStringLiteral("id")) == QLatin1String("sedmio");
        const bool ys = y.value(QStringLiteral("id")) == QLatin1String("sedmio");
        if (xs != ys)
            return xs;
        return x.value(QStringLiteral("name")).toString().localeAwareCompare(y.value(QStringLiteral("name")).toString()) < 0;
    });
    if (themes != m_themes) {
        m_themes = themes;
        Q_EMIT themesChanged();
    }

    // Следить за каталогами тем (появилась новая — в списке сразу).
    QStringList watch;
    for (const QString &dir : themeDirs()) {
        if (QDir(dir).exists())
            watch << dir;
    }
    if (!m_watcher.directories().isEmpty())
        m_watcher.removePaths(m_watcher.directories());
    if (!watch.isEmpty())
        m_watcher.addPaths(watch);
}

void Themes::choose(const QString &id)
{
    if (id.isEmpty() || id.contains(QLatin1Char('/')) || id.startsWith(QLatin1Char('.')))
        return;
    const QString dir = configDir();
    QDir().mkpath(dir);
    QSaveFile file(dir + QStringLiteral("/theme"));
    if (!file.open(QIODevice::WriteOnly) || file.write(id.toUtf8() + '\n') < 0 || !file.commit()) {
        setError(QStringLiteral("Не удалось сохранить выбор темы: %1").arg(file.errorString()));
        return;
    }
    setError(QString());
}

void Themes::chooseLayout(const QString &id)
{
    if (!layouts.contains(id) || id == m_layout)
        return;
    const QString dir = configDir();
    QDir().mkpath(dir);
    QSaveFile file(dir + QStringLiteral("/layout"));
    if (!file.open(QIODevice::WriteOnly) || file.write(id.toUtf8() + '\n') < 0 || !file.commit()) {
        setError(QStringLiteral("Не удалось сохранить расположение панелей: %1").arg(file.errorString()));
        return;
    }
    setError(QString());
    m_layout = id;
    Q_EMIT layoutChanged();
    // Оболочка следит за файлом, но QSaveFile заменяет его целиком —
    // просим перечитать и явно.
    QProcess::startDetached(QStringLiteral("quickshell"),
                            {QStringLiteral("ipc"), QStringLiteral("-p"), QStringLiteral("/usr/share/sedmio/shell"), QStringLiteral("call"),
                             QStringLiteral("layout"), QStringLiteral("reload")});
}

void Themes::setError(const QString &error)
{
    if (error == m_error)
        return;
    m_error = error;
    Q_EMIT errorChanged();
}
