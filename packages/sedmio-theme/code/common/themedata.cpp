#include "themedata.h"

#include <QColor>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLoggingCategory>
#include <QRegularExpression>
#include <QStandardPaths>

#include <cmath>

Q_LOGGING_CATEGORY(lcTheme, "sedmio.theme")

// Ресурс вшитой темы в статической библиотеке — подключить явно.
static void initBuiltinTheme()
{
    Q_INIT_RESOURCE(builtin_theme);
}

namespace
{
const QString defaultId = QStringLiteral("sedmio");
// Тема по умолчанию, вшитая в модуль (тот же файл, что в /usr/share).
const QString builtinFile = QStringLiteral(":/sedmio/theme/theme.json");

QString configHome()
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation);
}

QString dataHome()
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation);
}

// Какая тема выбрана: первая строка sedmio/theme. Имя — только буквы,
// цифры, «_», «-», «.» и не с точки: это имя каталога, никаких «../».
QString selectedId()
{
    const QString file = QStandardPaths::locate(QStandardPaths::GenericConfigLocation, QStringLiteral("sedmio/theme"));
    if (file.isEmpty())
        return defaultId;
    QFile f(file);
    if (!f.open(QIODevice::ReadOnly))
        return defaultId;
    const QString id = QString::fromUtf8(f.readLine(256)).trimmed();
    static const QRegularExpression valid(QStringLiteral("^[A-Za-z0-9_][A-Za-z0-9_.-]*$"));
    if (id.isEmpty())
        return defaultId;
    if (!valid.match(id).hasMatch()) {
        qCWarning(lcTheme) << "bad theme name in" << file << id;
        return defaultId;
    }
    return id;
}

void add(QVariantMap &out, const QString &key, const QJsonValue &value, const QString &path)
{
    if (value.isString()) {
        const QString text = value.toString();
        if (text.startsWith(QLatin1Char('#'))) {
            const QColor color = QColor::fromString(text);
            if (!color.isValid()) {
                qCWarning(lcTheme) << path << "bad color" << key << text;
                return;
            }
            out.insert(key, color);
        } else {
            out.insert(key, text);
        }
    } else if (value.isDouble()) {
        const double number = value.toDouble();
        if (std::floor(number) == number && std::abs(number) < 1e9)
            out.insert(key, int(number));
        else
            out.insert(key, number);
    } else if (value.isBool()) {
        out.insert(key, value.toBool());
    }
}

// Файл темы — плоским списком. ok = false: файла нет или он не JSON.
QVariantMap read(const QString &path, QString *name, bool *ok)
{
    *ok = false;
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
        return {};
    QJsonParseError error;
    const QJsonDocument doc = QJsonDocument::fromJson(file.readAll(), &error);
    if (error.error != QJsonParseError::NoError || !doc.isObject()) {
        qCWarning(lcTheme) << "broken theme" << path << error.errorString() << "at" << error.offset;
        return {};
    }
    QVariantMap out;
    const QJsonObject root = doc.object();
    for (auto it = root.begin(); it != root.end(); ++it) {
        if (it.key() == QLatin1String("name")) {
            *name = it->toString();
        } else if (it.key() == QLatin1String("description")) {
            continue;
        } else if (it->isObject()) {
            const QJsonObject section = it->toObject();
            for (auto sub = section.begin(); sub != section.end(); ++sub)
                add(out, sub.key(), *sub, path);
        } else {
            add(out, it.key(), *it, path);
        }
    }
    *ok = true;
    return out;
}

// Значение темы годится вместо значения по умолчанию: цвет вместо цвета,
// число вместо числа. Иначе опечатка в теме (радиус строкой) ломала бы
// вёрстку — лучше взять своё.
bool compatible(const QVariant &builtin, const QVariant &value)
{
    const auto number = [](const QVariant &v) {
        return v.typeId() == QMetaType::Int || v.typeId() == QMetaType::Double;
    };
    if (number(builtin))
        return number(value);
    return builtin.typeId() == value.typeId();
}
} // namespace

namespace Sedmio
{

ThemeData *ThemeData::instance()
{
    static ThemeData *data = new ThemeData; // живёт до конца процесса
    return data;
}

ThemeData::ThemeData()
{
    initBuiltinTheme();
    m_reload.setSingleShot(true);
    m_reload.setInterval(150);
    connect(&m_reload, &QTimer::timeout, this, &ThemeData::reload);
    connect(&m_watcher, &QFileSystemWatcher::fileChanged, &m_reload, qOverload<>(&QTimer::start));
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, &m_reload, qOverload<>(&QTimer::start));
    reload();
}

void ThemeData::reload()
{
    QString name;
    bool ok = false;
    QVariantMap values = read(builtinFile, &name, &ok);
    Q_ASSERT(ok);

    QString id = selectedId();
    QString directory;
    QString themeFile = QStandardPaths::locate(QStandardPaths::GenericDataLocation,
                                               QStringLiteral("sedmio/themes/%1/theme.json").arg(id));
    if (themeFile.isEmpty()) {
        if (id != defaultId)
            qCWarning(lcTheme) << "theme not found:" << id;
    } else {
        QString themeName;
        bool themeOk = false;
        const QVariantMap theme = read(themeFile, &themeName, &themeOk);
        if (themeOk) {
            for (auto it = theme.begin(); it != theme.end(); ++it) {
                if (values.contains(it.key()) && !compatible(values.value(it.key()), it.value())) {
                    qCWarning(lcTheme) << themeFile << "wrong type for" << it.key();
                    continue;
                }
                values.insert(it.key(), it.value());
            }
            directory = QFileInfo(themeFile).absolutePath();
            if (!themeName.isEmpty())
                name = themeName;
        }
    }
    if (directory.isEmpty())
        id = defaultId;

    values.insert(QStringLiteral("themeId"), id);
    values.insert(QStringLiteral("themeName"), name);
    values.insert(QStringLiteral("themeDirectory"), directory);

    const bool differs = values != m_values;
    m_values = values;

    // Следить: выбор темы и файл темы (правка на месте), их каталоги
    // (файл заменили целиком — старое наблюдение за ним пропало).
    const QString configDir = configHome() + QStringLiteral("/sedmio");
    QDir().mkpath(configDir);
    QStringList paths{configDir, configDir + QStringLiteral("/theme"), dataHome() + QStringLiteral("/sedmio/themes")};
    if (!directory.isEmpty())
        paths << directory << themeFile;
    watch(paths);

    if (differs)
        Q_EMIT changed();
}

void ThemeData::watch(const QStringList &paths)
{
    const QStringList old = m_watcher.files() + m_watcher.directories();
    if (!old.isEmpty())
        m_watcher.removePaths(old);
    QStringList existing;
    for (const QString &path : paths) {
        if (QFileInfo::exists(path))
            existing << path;
    }
    if (!existing.isEmpty())
        m_watcher.addPaths(existing);
}

} // namespace Sedmio
