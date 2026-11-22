#include "appimages.h"

#include <QCoreApplication>
#include <QCryptographicHash>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocale>
#include <QNetworkReply>
#include <QProcess>
#include <QRegularExpression>
#include <QSaveFile>
#include <QSet>
#include <QStandardPaths>
#include <QThread>
#include <QtEndian>

#include <cstdio>

namespace
{
using Re = QRegularExpression;

const QString api = QStringLiteral("https://api.github.com");
constexpr qint64 checkEvery = 6 * 3600;

QString appsDir()
{
    return QDir::homePath() + QStringLiteral("/Applications");
}
QString iconsDir()
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + QStringLiteral("/sedmio-store/appimages");
}
QString desktopDir()
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + QStringLiteral("/applications");
}

// Работа в своём потоке, итог — в главном (если объект ещё жив).
template<typename Result>
void inThread(QObject *owner, std::function<Result()> work, std::function<void(const Result &)> done)
{
    QPointer<QObject> guard(owner);
    QThread *thread = QThread::create([guard, work = std::move(work), done = std::move(done)] {
        const Result result = work();
        QMetaObject::invokeMethod(
            QCoreApplication::instance(),
            [guard, done, result] {
                if (guard)
                    done(result);
            },
            Qt::QueuedConnection);
    });
    QObject::connect(thread, &QThread::finished, thread, &QObject::deleteLater);
    thread->start(QThread::LowPriority);
}

template<typename T>
T le(const QByteArray &data, qsizetype at)
{
    if (at < 0 || at + qsizetype(sizeof(T)) > data.size())
        return 0;
    return qFromLittleEndian<T>(reinterpret_cast<const uchar *>(data.constData() + at));
}

QString megabytes(qint64 bytes)
{
    const double mb = bytes / 1048576.0;
    return mb < 10 ? QLocale().toString(mb, 'f', 1) : QString::number(qRound(mb));
}

// Ключи группы [Desktop Entry] (с переводами: Name[ru]).
QHash<QString, QString> desktopKeys(const QByteArray &text)
{
    QHash<QString, QString> keys;
    bool entry = false;
    for (const QByteArray &raw : text.split('\n')) {
        const QString line = QString::fromUtf8(raw).trimmed();
        if (line.startsWith(u'[')) {
            entry = line == QLatin1String("[Desktop Entry]");
            continue;
        }
        const qsizetype eq = line.indexOf(u'=');
        if (entry && eq > 0 && !line.startsWith(u'#'))
            keys.insert(line.left(eq).trimmed(), line.mid(eq + 1).trimmed());
    }
    return keys;
}

QString localized(const QHash<QString, QString> &keys, const QString &key)
{
    const QString locale = QLocale().name(); // ru_RU
    for (const QString &k : {key + u'[' + locale + u']', key + u'[' + locale.section(u'_', 0, 0) + u']', key})
        if (!keys.value(k).isEmpty())
            return keys.value(k);
    return {};
}

// Exec из .desktop внутри AppImage указывает на AppRun или файл внутри
// образа — меняем программу на сам файл AppImage, аргументы (%U) оставляем.
QString rewriteExec(const QString &value, const QString &file)
{
    QStringList tokens;
    QString current;
    bool quoted = false;
    for (qsizetype i = 0; i < value.size(); ++i) {
        const QChar c = value.at(i);
        if (c == u'"')
            quoted = !quoted;
        if (c.isSpace() && !quoted) {
            if (!current.isEmpty())
                tokens << current;
            current.clear();
            continue;
        }
        current += c;
        if (c == u'\\' && i + 1 < value.size())
            current += value.at(++i);
    }
    if (!current.isEmpty())
        tokens << current;
    if (!tokens.isEmpty() && tokens.constFirst() == QLatin1String("env")) {
        tokens.removeFirst();
        while (!tokens.isEmpty() && tokens.constFirst().contains(u'='))
            tokens.removeFirst();
    }
    if (!tokens.isEmpty())
        tokens.removeFirst();
    QString path = file;
    for (const char *special : {"\\", "\"", "`", "$"})
        path.replace(QLatin1String(special), u'\\' + QLatin1String(special));
    path = u'"' + path + u'"';
    path.replace(u'\\', QLatin1String("\\\\")); // экранирование строки .desktop
    return tokens.isEmpty() ? path : path + u' ' + tokens.join(u' ');
}

QByteArray makeDesktop(const QByteArray &source, const QString &id, const QString &file, const QString &icon, const QString &fallbackName)
{
    QStringList out;
    bool keep = false;
    bool sawEntry = false;
    for (const QByteArray &raw : source.split('\n')) {
        const QString line = QString::fromUtf8(raw).trimmed();
        if (line.startsWith(u'[')) {
            keep = line == QLatin1String("[Desktop Entry]") || line.startsWith(QLatin1String("[Desktop Action "));
            if (keep) {
                if (!out.isEmpty())
                    out << QString();
                out << line;
            }
            if (line == QLatin1String("[Desktop Entry]")) {
                sawEntry = true;
                out << QStringLiteral("X-Sedmio-AppImage=") + id;
            }
            continue;
        }
        if (!keep || line.isEmpty() || line.startsWith(u'#'))
            continue;
        const QString key = line.section(u'=', 0, 0).trimmed();
        const QString value = line.section(u'=', 1).trimmed();
        if (key == QLatin1String("TryExec") || key == QLatin1String("DBusActivatable") || key == QLatin1String("X-Sedmio-AppImage")
            || key.startsWith(QLatin1String("X-AppImage-Integrate")))
            continue;
        if (key == QLatin1String("Exec"))
            out << QStringLiteral("Exec=") + rewriteExec(value, file);
        else if (key == QLatin1String("Icon"))
            out << QStringLiteral("Icon=") + (icon.isEmpty() ? QStringLiteral("application-x-executable") : icon);
        else
            out << line;
    }
    if (!sawEntry) {
        out = QStringList{QStringLiteral("[Desktop Entry]"),
                          QStringLiteral("X-Sedmio-AppImage=") + id,
                          QStringLiteral("Type=Application"),
                          QStringLiteral("Name=") + fallbackName,
                          QStringLiteral("Exec=") + rewriteExec(QStringLiteral("x"), file),
                          QStringLiteral("Icon=") + (icon.isEmpty() ? QStringLiteral("application-x-executable") : icon),
                          QStringLiteral("Categories=Utility;")};
    }
    out.prepend(QStringLiteral("# Добавлено «Программами» Sedmio: удаляйте там же — вместе с файлом %1").arg(file));
    return (out.join(u'\n') + u'\n').toUtf8();
}

// Версия из имени файла: Foo-1.2.3-x86_64.AppImage → 1.2.3.
QString versionFromName(const QString &name)
{
    static const Re re(QStringLiteral(R"re((?:^|[-_ ])v?(\d+(?:\.\d+)+(?:[-.~+]?(?:alpha|beta|rc|pre)\.?\d*)?))re"), Re::CaseInsensitiveOption);
    const auto m = re.match(name);
    return m.hasMatch() ? m.captured(1) : QString();
}

QString slug(QString text)
{
    text = text.toLower();
    text.replace(Re(QStringLiteral("[^a-z0-9._-]+")), QStringLiteral("-"));
    text.replace(Re(QStringLiteral("^[-.]+|[-.]+$")), QString());
    return text.left(64);
}

// Имя файла без версии и архитектуры: ZCode-3.18.2-linux-x64.AppImage → zcode.
QString baseName(const QString &file)
{
    QString name = QFileInfo(file).fileName();
    name.remove(Re(QStringLiteral("\\.appimage$"), Re::CaseInsensitiveOption));
    name.remove(Re(QStringLiteral("[-_ ]v?\\d+(\\.\\d+)+.*$"), Re::CaseInsensitiveOption));
    name.remove(Re(QStringLiteral("[-_ ](linux|x86[-_]64|amd64|x64)([-_ ].*)?$"), Re::CaseInsensitiveOption));
    name.remove(Re(QStringLiteral("\\(\\d+\\)$")));
    return name.trimmed();
}

QString iconMime(const QString &ext)
{
    return ext == QLatin1String("svg") ? QStringLiteral("image/svg+xml") : ext == QLatin1String("xpm") ? QStringLiteral("image/x-xpixmap") : QStringLiteral("image/png");
}
} // namespace

AppImages *AppImages::instance()
{
    static AppImages *images = new AppImages;
    QJSEngine::setObjectOwnership(images, QJSEngine::CppOwnership);
    return images;
}

AppImages::AppImages(QObject *parent)
    : QObject(parent)
{
    m_network.setTransferTimeout(30000);
    load();
    rebuild();
}

QString AppImages::statePath() const
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericStateLocation) + QStringLiteral("/sedmio-store/appimages.json");
}

void AppImages::load()
{
    QFile file(statePath());
    if (file.open(QIODevice::ReadOnly))
        m_state = QJsonDocument::fromJson(file.readAll()).object().toVariantMap();
    // Файл удалили руками — забываем и пункт меню.
    bool changed = false;
    for (auto it = m_state.begin(); it != m_state.end();) {
        if (it.key().startsWith(u'@')) {
            ++it;
            continue;
        }
        const QVariantMap e = it.value().toMap();
        if (!QFile::exists(e.value(QStringLiteral("file")).toString())) {
            QFile::remove(e.value(QStringLiteral("desktop")).toString());
            QFile::remove(e.value(QStringLiteral("icon")).toString());
            it = m_state.erase(it);
            changed = true;
        } else {
            ++it;
        }
    }
    if (changed)
        save();
}

void AppImages::save() const
{
    QDir().mkpath(QFileInfo(statePath()).path());
    QSaveFile file(statePath());
    if (file.open(QIODevice::WriteOnly)) {
        file.write(QJsonDocument(QJsonObject::fromVariantMap(m_state)).toJson());
        file.commit();
    }
}

void AppImages::rebuild()
{
    QVariantList list;
    for (auto it = m_state.cbegin(); it != m_state.cend(); ++it) {
        if (it.key().startsWith(u'@'))
            continue;
        const QVariantMap e = it.value().toMap();
        const QString icon = e.value(QStringLiteral("icon")).toString();
        list << QVariantMap{
            {QStringLiteral("id"), it.key()},
            {QStringLiteral("name"), e.value(QStringLiteral("name"))},
            {QStringLiteral("comment"), e.value(QStringLiteral("comment"))},
            {QStringLiteral("icon"), icon.isEmpty() ? QString() : QUrl::fromLocalFile(icon).toString() + QStringLiteral("?") + e.value(QStringLiteral("tag")).toString() + e.value(QStringLiteral("size")).toString()},
            {QStringLiteral("version"), e.value(QStringLiteral("version")).toString().isEmpty() ? e.value(QStringLiteral("tag")) : e.value(QStringLiteral("version"))},
            {QStringLiteral("file"), e.value(QStringLiteral("file"))},
            {QStringLiteral("size"), e.value(QStringLiteral("size"))},
            {QStringLiteral("github"), e.value(QStringLiteral("github"))},
            {QStringLiteral("update"), e.value(QStringLiteral("latest")).toMap().value(QStringLiteral("tag")).toString()},
            {QStringLiteral("desktop"), QStringLiteral("appimage-") + it.key() + QStringLiteral(".desktop")},
            {QStringLiteral("checkError"), e.value(QStringLiteral("checkError"))},
            {QStringLiteral("selfUpdating"), !e.value(QStringLiteral("pattern")).toString().isEmpty()},
        };
    }
    std::sort(list.begin(), list.end(), [](const QVariant &a, const QVariant &b) {
        return QString::localeAwareCompare(a.toMap().value(QStringLiteral("name")).toString(), b.toMap().value(QStringLiteral("name")).toString()) < 0;
    });
    m_list = list;
    Q_EMIT listChanged();
}

void AppImages::setWork(const QString &id, const QString &text, double progress, const QString &error, bool done)
{
    m_work.insert(id, QVariantMap{{QStringLiteral("text"), text}, {QStringLiteral("progress"), progress}, {QStringLiteral("error"), error}, {QStringLiteral("done"), done}});
    Q_EMIT workChanged();
}

void AppImages::dismiss(const QString &id)
{
    if (m_work.remove(id) > 0)
        Q_EMIT workChanged();
}

void AppImages::cancel(const QString &id)
{
    if (QNetworkReply *reply = m_downloads.value(id))
        reply->abort();
}

QVariantMap AppImages::get(const QString &id) const
{
    for (const QVariant &v : m_list)
        if (v.toMap().value(QStringLiteral("id")).toString() == id)
            return v.toMap();
    return {};
}

QString AppImages::byDesktop(const QString &desktopId) const
{
    QString id = desktopId;
    if (id.endsWith(QLatin1String(".desktop")))
        id.chop(8);
    if (!id.startsWith(QLatin1String("appimage-")))
        return {};
    id = id.mid(9);
    return m_state.contains(id) ? id : QString();
}

QString AppImages::parseRepo(const QString &text)
{
    const QString t = text.trimmed();
    static const Re url(QStringLiteral(R"re(github\.com[/:]([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+?)(?:\.git)?(?:[/#?].*)?$)re"));
    static const Re bare(QStringLiteral(R"re(^([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)$)re"));
    auto m = url.match(t);
    if (!m.hasMatch())
        m = bare.match(t);
    return m.hasMatch() ? m.captured(1) + u'/' + m.captured(2) : QString();
}

// --- Разбор файла -----------------------------------------------------------

AppImages::Inspected AppImages::inspectFile(const QString &path)
{
    Inspected r;
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly)) {
        r.error = QStringLiteral("Файл не открывается");
        return r;
    }
    r.size = f.size();
    const QByteArray head = f.read(64);
    if (head.size() < 64 || !head.startsWith("\x7f" "ELF")) {
        r.error = QStringLiteral("Это не AppImage: файл — не программа для Linux");
        return r;
    }
    if (head.at(4) != 2 || head.at(5) != 1 || le<quint16>(head, 0x12) != 62) {
        r.error = QStringLiteral("Эта сборка не для этого компьютера (нужна x86_64, например не ARM)");
        return r;
    }
    if (head.mid(8, 3) == QByteArray("AI\x01", 3)) {
        r.error = QStringLiteral("Это AppImage старого формата (тип 1) — его не поддерживаем; поищите новую сборку");
        return r;
    }
    // Образ squashfs — сразу за программой запуска (концом её таблицы
    // разделов ELF).
    const quint64 shoff = le<quint64>(head, 0x28);
    const quint16 shentsize = le<quint16>(head, 0x3A), shnum = le<quint16>(head, 0x3C), shstrndx = le<quint16>(head, 0x3E);
    r.offset = qint64(shoff + quint64(shentsize) * shnum);
    if (r.offset <= 64 || r.offset >= r.size || !f.seek(r.offset) || f.read(4) != "hsqs") {
        r.error = QStringLiteral("Внутри нет образа AppImage — файл повреждён или это просто программа");
        return r;
    }
    // .upd_info — откуда обновлять (gh-releases-zsync|владелец|проект|…).
    if (shentsize >= 64 && shnum > 0 && shnum < 256 && shstrndx < shnum && f.seek(qint64(shoff))) {
        const QByteArray sh = f.read(qint64(shentsize) * shnum);
        const qsizetype s = qsizetype(shstrndx) * shentsize;
        QByteArray names;
        if (f.seek(qint64(le<quint64>(sh, s + 0x18))))
            names = f.read(qMin<qint64>(qint64(le<quint64>(sh, s + 0x20)), 65536));
        for (int i = 0; i < shnum; ++i) {
            const qsizetype at = qsizetype(i) * shentsize;
            const quint32 nameAt = le<quint32>(sh, at);
            if (nameAt >= quint32(names.size()))
                continue;
            if (qstrcmp(names.constData() + nameAt, ".upd_info") != 0)
                continue;
            if (f.seek(qint64(le<quint64>(sh, at + 0x18)))) {
                QByteArray info = f.read(qMin<qint64>(qint64(le<quint64>(sh, at + 0x20)), 4096));
                info.truncate(info.indexOf('\0') < 0 ? info.size() : info.indexOf('\0'));
                r.updateInfo = QString::fromUtf8(info).trimmed();
            }
        }
    }
    f.close();

    // Что в образе: unsquashfs читает его как архив, ничего не запуская.
    const QString offset = QString::number(r.offset);
    auto run = [&](const QStringList &args, qint64 limit, QByteArray *out) {
        QProcess p;
        p.setProcessChannelMode(QProcess::SeparateChannels);
        p.start(QStringLiteral("unsquashfs"), QStringList{QStringLiteral("-o"), offset} + args);
        if (!p.waitForStarted(5000))
            return false;
        QByteArray data;
        while (p.state() != QProcess::NotRunning) {
            p.waitForReadyRead(60000);
            data += p.readAllStandardOutput();
            if (data.size() > limit) {
                p.kill();
                p.waitForFinished(2000);
                return false;
            }
        }
        data += p.readAllStandardOutput();
        *out = data;
        return p.exitStatus() == QProcess::NormalExit && p.exitCode() == 0;
    };
    QByteArray listing;
    if (!run({QStringLiteral("-lls"), path}, 64 * 1024 * 1024, &listing)) {
        r.error = QStringLiteral("Не получилось прочитать, что внутри файла (unsquashfs)");
        return r;
    }
    QSet<QString> files;
    QHash<QString, QString> links;
    static const Re entry(QStringLiteral(R"re(^([-dlcbps])\S*\s+\S+\s+[\d,]+\s+\S+\s+\S+\s+squashfs-root/(.+?)(?: -> (.+))?$)re"));
    for (const QByteArray &raw : listing.split('\n')) {
        const auto m = entry.match(QString::fromUtf8(raw));
        if (!m.hasMatch())
            continue;
        if (m.captured(1) == QLatin1String("l"))
            links.insert(m.captured(2), m.captured(3));
        else if (m.captured(1) == QLatin1String("-"))
            files.insert(m.captured(2));
    }
    auto resolve = [&](QString p) -> QString {
        for (int hop = 0; hop < 8; ++hop) {
            if (files.contains(p))
                return p;
            if (!links.contains(p))
                return {};
            const QString target = links.value(p);
            if (target.startsWith(u'/'))
                return {};
            p = QDir::cleanPath(QFileInfo(p).path() + u'/' + target);
            if (p.startsWith(QLatin1String("..")))
                return {};
            if (p.startsWith(QLatin1String("./")))
                p = p.mid(2);
        }
        return {};
    };
    auto cat = [&](const QString &p, qint64 limit) {
        QByteArray data;
        return run({QStringLiteral("-cat"), path, p}, limit, &data) ? data : QByteArray();
    };

    QStringList desktops;
    for (const QString &p : files)
        if (!p.contains(u'/') && p.endsWith(QLatin1String(".desktop")))
            desktops << p;
    for (auto it = links.cbegin(); it != links.cend(); ++it)
        if (!it.key().contains(u'/') && it.key().endsWith(QLatin1String(".desktop")) && !resolve(it.key()).isEmpty())
            desktops << it.key();
    desktops.sort();
    QHash<QString, QString> keys;
    if (!desktops.isEmpty()) {
        r.desktopName = desktops.constFirst();
        r.desktop = cat(resolve(r.desktopName), 256 * 1024);
        keys = desktopKeys(r.desktop);
    }
    r.name = localized(keys, QStringLiteral("Name"));
    r.comment = localized(keys, QStringLiteral("Comment"));
    r.version = keys.value(QStringLiteral("X-AppImage-Version"));

    // Значок: из темы внутри образа, крупный или векторный, иначе .DirIcon.
    const QString icon = keys.value(QStringLiteral("Icon"));
    QStringList candidates;
    if (!icon.isEmpty() && !icon.contains(u'/')) {
        candidates << icon + QStringLiteral(".svg") << QStringLiteral("usr/share/icons/hicolor/scalable/apps/") + icon + QStringLiteral(".svg");
        QList<QPair<int, QString>> pngs;
        static const Re sized(QStringLiteral(R"re(^usr/share/icons/hicolor/(\d+)x\d+/apps/(.+)\.png$)re"));
        for (const QString &p : files) {
            const auto m = sized.match(p);
            if (m.hasMatch() && m.captured(2) == icon)
                pngs.append({m.captured(1).toInt(), p});
        }
        for (const QString &p : links.keys()) {
            const auto m = sized.match(p);
            if (m.hasMatch() && m.captured(2) == icon)
                pngs.append({m.captured(1).toInt(), p});
        }
        std::sort(pngs.begin(), pngs.end(), [](const auto &a, const auto &b) {
            // 256…512 — лучше всего; больше — тяжело, меньше — мыльно.
            auto rank = [](int s) { return s >= 256 && s <= 512 ? 10000 + s : s > 512 ? 5000 - s / 100 : s; };
            return rank(a.first) > rank(b.first);
        });
        for (const auto &png : pngs)
            candidates << png.second;
        candidates << icon + QStringLiteral(".png") << QStringLiteral("usr/share/pixmaps/") + icon + QStringLiteral(".png")
                   << icon + QStringLiteral(".svgz") << icon + QStringLiteral(".xpm");
    }
    candidates << QStringLiteral(".DirIcon");
    for (const QString &c : candidates) {
        const QString p = resolve(c);
        if (p.isEmpty())
            continue;
        const QByteArray data = cat(p, 8 * 1024 * 1024);
        if (data.isEmpty())
            continue;
        if (data.startsWith("\x89PNG"))
            r.iconExt = QStringLiteral("png");
        else if (data.startsWith("\x1f\x8b"))
            r.iconExt = QStringLiteral("svgz");
        else if (data.left(512).contains("<svg"))
            r.iconExt = QStringLiteral("svg");
        else if (data.startsWith("/* XPM"))
            r.iconExt = QStringLiteral("xpm");
        else
            continue;
        r.icon = data;
        break;
    }
    if (r.name.isEmpty())
        r.name = baseName(path);
    if (r.version.isEmpty())
        r.version = versionFromName(QFileInfo(path).fileName());
    return r;
}

QString AppImages::makeId(const Inspected &in, const QString &path) const
{
    QString id;
    if (!in.desktopName.isEmpty())
        id = slug(in.desktopName.chopped(8));
    if (id.isEmpty())
        id = slug(baseName(path));
    if (id.isEmpty())
        id = QStringLiteral("program");
    return id;
}

// gh-releases-zsync|владелец|проект|latest|Foo-*x86_64.AppImage.zsync
static QPair<QString, QString> githubFromUpdateInfo(const QString &info)
{
    const QStringList parts = info.split(u'|');
    if (parts.size() >= 5 && (parts.at(0) == QLatin1String("gh-releases-zsync") || parts.at(0) == QLatin1String("gh-releases-direct"))) {
        QString pattern = parts.at(4);
        if (pattern.endsWith(QLatin1String(".zsync")))
            pattern.chop(6);
        return {parts.at(1) + u'/' + parts.at(2), pattern};
    }
    return {};
}

void AppImages::inspect(const QString &path, const QJSValue &done)
{
    QJSValue callback = done;
    inThread<Inspected>(
        this, [path] { return inspectFile(path); },
        [this, path, callback](const Inspected &in) mutable {
            QVariantMap result{{QStringLiteral("ok"), in.error.isEmpty()}, {QStringLiteral("error"), in.error}, {QStringLiteral("path"), path}};
            if (in.error.isEmpty()) {
                const QString id = makeId(in, path);
                const QVariantMap existing = m_state.value(id).toMap();
                const auto gh = githubFromUpdateInfo(in.updateInfo);
                result.insert({
                    {QStringLiteral("id"), id},
                    {QStringLiteral("name"), in.name},
                    {QStringLiteral("comment"), in.comment},
                    {QStringLiteral("version"), in.version},
                    {QStringLiteral("size"), in.size},
                    {QStringLiteral("github"), gh.first.isEmpty() ? existing.value(QStringLiteral("github")).toString() : gh.first},
                    {QStringLiteral("selfUpdating"), !gh.first.isEmpty()},
                    {QStringLiteral("icon"), in.icon.isEmpty() || in.iconExt == QLatin1String("svgz") ? QString()
                                                 : QStringLiteral("data:") + iconMime(in.iconExt) + QStringLiteral(";base64,") + QString::fromLatin1(in.icon.toBase64())},
                    {QStringLiteral("existing"), existing.isEmpty() ? QString() : id},
                    {QStringLiteral("existingVersion"), existing.value(QStringLiteral("version"))},
                    {QStringLiteral("alreadyThere"), !existing.isEmpty() && QFileInfo(existing.value(QStringLiteral("file")).toString()).canonicalFilePath() == QFileInfo(path).canonicalFilePath()},
                });
            }
            if (callback.isCallable()) {
                QJSEngine *engine = qjsEngine(this);
                callback.call({engine ? engine->toScriptValue(result) : QJSValue()});
            }
        });
}

// --- Установка ---------------------------------------------------------------

namespace
{
struct Placed {
    QString error;
    QString id;
    AppImages::Inspected in;
    QString file, icon, desktop;
};
} // namespace

// path — откуда взять файл; ownsFile — это наш временный (скачанный):
// после установки его не остаётся. Файл человека переносим, а если он на
// другом диске (флешка) — копируем и оригинал не трогаем.
void AppImages::install(const QString &workId, const QString &path, bool ownsFile, const QVariantMap &meta)
{
    setWork(workId, QStringLiteral("Смотрю, что внутри…"), -1);
    const QString forcedId = meta.value(QStringLiteral("id")).toString();
    inThread<Placed>(
        this,
        [this, path, ownsFile, forcedId] {
            Placed r;
            r.in = inspectFile(path);
            if (!r.in.error.isEmpty()) {
                r.error = r.in.error;
                if (ownsFile)
                    QFile::remove(path);
                return r;
            }
            r.id = forcedId.isEmpty() ? makeId(r.in, path) : forcedId;
            QDir().mkpath(appsDir());
            r.file = appsDir() + u'/' + r.id + QStringLiteral(".AppImage");
            if (QFileInfo(path).canonicalFilePath() != QFileInfo(r.file).canonicalFilePath()) {
                const QString next = appsDir() + QStringLiteral("/.") + r.id + QStringLiteral(".AppImage.new");
                QFile::remove(next);
                if (!QFile::rename(path, next)) {
                    if (!QFile::copy(path, next)) {
                        QFile::remove(next);
                        r.error = QStringLiteral("Не получилось положить файл в %1 — хватает ли места?").arg(appsDir());
                        return r;
                    }
                    if (ownsFile)
                        QFile::remove(path);
                }
                // Поверх старой версии разом: запущенная доработает со старой.
                if (std::rename(QFile::encodeName(next).constData(), QFile::encodeName(r.file).constData()) != 0) {
                    QFile::remove(next);
                    r.error = QStringLiteral("Не получилось заменить %1").arg(r.file);
                    return r;
                }
            }
            QFile(r.file).setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner | QFileDevice::ReadGroup
                                         | QFileDevice::ExeGroup | QFileDevice::ReadOther | QFileDevice::ExeOther);
            QDir().mkpath(iconsDir());
            for (const char *ext : {"png", "svg", "svgz", "xpm"})
                QFile::remove(iconsDir() + u'/' + r.id + u'.' + QLatin1String(ext));
            if (!r.in.icon.isEmpty()) {
                r.icon = iconsDir() + u'/' + r.id + u'.' + r.in.iconExt;
                QSaveFile icon(r.icon);
                if (icon.open(QIODevice::WriteOnly)) {
                    icon.write(r.in.icon);
                    icon.commit();
                }
            }
            QDir().mkpath(desktopDir());
            r.desktop = desktopDir() + QStringLiteral("/appimage-") + r.id + QStringLiteral(".desktop");
            QSaveFile desktop(r.desktop);
            if (desktop.open(QIODevice::WriteOnly)) {
                desktop.write(makeDesktop(r.in.desktop, r.id, r.file, r.icon, r.in.name));
                desktop.commit();
            }
            return r;
        },
        [this, workId, meta](const Placed &r) {
            if (!r.error.isEmpty()) {
                setWork(workId, QString(), -1, r.error);
                return;
            }
            QVariantMap e = m_state.value(r.id).toMap();
            const auto gh = githubFromUpdateInfo(r.in.updateInfo);
            const QString github = !meta.value(QStringLiteral("github")).toString().isEmpty() ? meta.value(QStringLiteral("github")).toString()
                : !gh.first.isEmpty()                                                       ? gh.first
                                                                                            : e.value(QStringLiteral("github")).toString();
            if (github != e.value(QStringLiteral("github")).toString())
                e.remove(QStringLiteral("tag"));
            e.insert(QStringLiteral("github"), github);
            if (!gh.second.isEmpty())
                e.insert(QStringLiteral("pattern"), gh.second);
            e.insert(QStringLiteral("name"), r.in.name);
            e.insert(QStringLiteral("comment"), r.in.comment);
            e.insert(QStringLiteral("version"), r.in.version);
            e.insert(QStringLiteral("file"), r.file);
            e.insert(QStringLiteral("icon"), r.icon);
            e.insert(QStringLiteral("desktop"), r.desktop);
            e.insert(QStringLiteral("size"), r.in.size);
            // Скачали выпуск — знаем, какой он; файл со стороны — узнаем
            // при проверке (checkOne).
            if (meta.contains(QStringLiteral("tag")))
                e.insert(QStringLiteral("tag"), meta.value(QStringLiteral("tag")));
            else if (!meta.contains(QStringLiteral("id")))
                e.remove(QStringLiteral("tag"));
            e.remove(QStringLiteral("latest"));
            if (!e.contains(QStringLiteral("added")))
                e.insert(QStringLiteral("added"), QDateTime::currentSecsSinceEpoch());
            m_state.insert(r.id, e);
            save();
            rebuild();
            m_work.remove(workId);
            Q_EMIT workChanged();
            if (workId == QLatin1String("@add"))
                Q_EMIT added(r.id);
            if (!github.isEmpty() && !e.contains(QStringLiteral("tag")))
                checkOne(r.id);
        });
}

void AppImages::add(const QString &path, const QString &github)
{
    QString local = path;
    if (local.startsWith(QLatin1String("file:")))
        local = QUrl(local).toLocalFile();
    install(QStringLiteral("@add"), local, false, {{QStringLiteral("github"), parseRepo(github)}});
}

void AppImages::remove(const QString &id)
{
    const QVariantMap e = m_state.value(id).toMap();
    if (e.isEmpty())
        return;
    cancel(id);
    QFile::remove(e.value(QStringLiteral("file")).toString());
    QFile::remove(e.value(QStringLiteral("desktop")).toString());
    QFile::remove(e.value(QStringLiteral("icon")).toString());
    m_state.remove(id);
    m_work.remove(id);
    save();
    rebuild();
    Q_EMIT workChanged();
}

bool AppImages::launch(const QString &id) const
{
    const QString file = m_state.value(id).toMap().value(QStringLiteral("file")).toString();
    if (file.isEmpty() || !QFile::exists(file))
        return false;
    return QProcess::startDetached(QStringLiteral("/usr/lib/sedmio/launch"), {QStringLiteral("appimage-") + id, file}, QDir::homePath());
}

// --- GitHub -------------------------------------------------------------------

void AppImages::apiGet(const QString &path, std::function<void(const QVariantMap &, const QString &error)> done)
{
    QNetworkRequest request{QUrl(api + path)};
    request.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("sedmio-store"));
    request.setRawHeader("Accept", "application/vnd.github+json");
    request.setRawHeader("X-GitHub-Api-Version", "2022-11-28");
    QNetworkReply *reply = m_network.get(request);
    connect(reply, &QNetworkReply::finished, this, [reply, done] {
        reply->deleteLater();
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        if (status == 404) {
            done({}, QStringLiteral("Не нашлось: такого проекта нет или у него нет выпусков"));
            return;
        }
        if (status == 403 || status == 429) {
            done({}, QStringLiteral("GitHub ограничил число запросов — попробуйте через час"));
            return;
        }
        if (reply->error() != QNetworkReply::NoError) {
            done({}, status >= 500 ? QStringLiteral("GitHub сейчас не отвечает — попробуйте позже") : QStringLiteral("Нет связи с GitHub — проверьте интернет"));
            return;
        }
        done(QJsonDocument::fromJson(reply->readAll()).object().toVariantMap(), {});
    });
}

QVariantMap AppImages::pickAsset(const QVariantMap &release, const QString &pattern)
{
    static const Re foreign(QStringLiteral("aarch64|arm64|armv7|armhf|arm32|i386|i686|riscv"), Re::CaseInsensitiveOption);
    static const Re ours(QStringLiteral("x86[_-]64|amd64|x64"), Re::CaseInsensitiveOption);
    const Re wanted(pattern.isEmpty() ? QString() : Re::wildcardToRegularExpression(pattern, Re::UnanchoredWildcardConversion));
    QVariantMap best;
    int bestScore = -1;
    for (const QVariant &v : release.value(QStringLiteral("assets")).toList()) {
        const QVariantMap a = v.toMap();
        const QString name = a.value(QStringLiteral("name")).toString();
        if (!name.endsWith(QLatin1String(".AppImage"), Qt::CaseInsensitive))
            continue;
        int score = 0;
        if (!pattern.isEmpty()) {
            if (!Re(u'^' + wanted.pattern() + u'$').match(name).hasMatch())
                continue;
            score = 10;
        } else {
            if (foreign.match(name).hasMatch())
                continue;
            score = ours.match(name).hasMatch() ? 2 : 1;
        }
        if (score > bestScore) {
            bestScore = score;
            best = {{QStringLiteral("asset"), name},
                    {QStringLiteral("url"), a.value(QStringLiteral("browser_download_url"))},
                    {QStringLiteral("size"), a.value(QStringLiteral("size"))},
                    {QStringLiteral("digest"), a.value(QStringLiteral("digest"))}};
        }
    }
    if (!best.isEmpty()) {
        best.insert(QStringLiteral("tag"), release.value(QStringLiteral("tag_name")));
        best.insert(QStringLiteral("title"), release.value(QStringLiteral("name")).toString().isEmpty() ? release.value(QStringLiteral("tag_name")) : release.value(QStringLiteral("name")));
        const QDateTime published = QDateTime::fromString(release.value(QStringLiteral("published_at")).toString(), Qt::ISODate);
        best.insert(QStringLiteral("published"), published.isValid() ? QLocale().toString(published.toLocalTime().date(), QStringLiteral("d MMMM yyyy")) : QString());
    }
    return best;
}

void AppImages::findRelease(const QString &text, const QJSValue &done)
{
    QJSValue callback = done;
    const QString repo = parseRepo(text);
    auto reply = [this, callback](const QVariantMap &result) mutable {
        if (callback.isCallable()) {
            QJSEngine *engine = qjsEngine(this);
            callback.call({engine ? engine->toScriptValue(result) : QJSValue()});
        }
    };
    if (repo.isEmpty()) {
        reply({{QStringLiteral("ok"), false}, {QStringLiteral("error"), QStringLiteral("Нужна ссылка на проект GitHub или «владелец/проект»")}});
        return;
    }
    apiGet(QStringLiteral("/repos/%1/releases/latest").arg(repo), [repo, reply](const QVariantMap &release, const QString &error) mutable {
        if (!error.isEmpty()) {
            reply({{QStringLiteral("ok"), false}, {QStringLiteral("error"), error}});
            return;
        }
        QVariantMap asset = pickAsset(release, {});
        if (asset.isEmpty()) {
            reply({{QStringLiteral("ok"), false},
                   {QStringLiteral("error"), QStringLiteral("В последнем выпуске (%1) нет AppImage для этого компьютера").arg(release.value(QStringLiteral("tag_name")).toString())}});
            return;
        }
        asset.insert(QStringLiteral("ok"), true);
        asset.insert(QStringLiteral("repo"), repo);
        reply(asset);
    });
}

void AppImages::download(const QString &workId, const QVariantMap &release, std::function<void(const QString &)> done)
{
    const QString name = release.value(QStringLiteral("asset")).toString();
    const qint64 expected = release.value(QStringLiteral("size")).toLongLong();
    QDir().mkpath(appsDir());
    const QString part = appsDir() + QStringLiteral("/.") + slug(name) + QStringLiteral(".part");
    auto file = std::make_shared<QFile>(part);
    if (!file->open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        setWork(workId, QString(), -1, QStringLiteral("Не получилось создать файл в %1").arg(appsDir()));
        return;
    }
    auto hash = std::make_shared<QCryptographicHash>(QCryptographicHash::Sha256);
    QNetworkRequest request{QUrl(release.value(QStringLiteral("url")).toString())};
    request.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("sedmio-store"));
    request.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::NoLessSafeRedirectPolicy);
    QNetworkReply *reply = m_network.get(request);
    m_downloads.insert(workId, reply);
    setWork(workId, QStringLiteral("Скачиваю %1…").arg(name), 0);
    connect(reply, &QNetworkReply::readyRead, this, [reply, file, hash] {
        const QByteArray chunk = reply->readAll();
        hash->addData(chunk);
        file->write(chunk);
    });
    connect(reply, &QNetworkReply::downloadProgress, this, [this, workId, name, expected](qint64 got, qint64 total) {
        if (total <= 0)
            total = expected;
        setWork(workId, QStringLiteral("Скачиваю %1 — %2 из %3 МБ").arg(name, megabytes(got), megabytes(total)), total > 0 ? double(got) / total : -1);
    });
    connect(reply, &QNetworkReply::finished, this, [this, reply, file, hash, part, workId, expected, release, done] {
        reply->deleteLater();
        m_downloads.remove(workId);
        const QByteArray rest = reply->readAll();
        hash->addData(rest);
        file->write(rest);
        file->close();
        auto fail = [&](const QString &error) {
            QFile::remove(part);
            if (error.isEmpty())
                dismiss(workId);
            else
                setWork(workId, QString(), -1, error);
        };
        if (reply->error() == QNetworkReply::OperationCanceledError)
            return fail({});
        if (reply->error() != QNetworkReply::NoError)
            return fail(QStringLiteral("Скачать не получилось: %1").arg(reply->errorString()));
        if (expected > 0 && file->size() != expected)
            return fail(QStringLiteral("Файл скачался не целиком — попробуйте ещё раз"));
        // GitHub даёт контрольную сумму файла выпуска — сверяем.
        const QString digest = release.value(QStringLiteral("digest")).toString();
        if (digest.startsWith(QLatin1String("sha256:")) && digest.mid(7).toLower() != QString::fromLatin1(hash->result().toHex()))
            return fail(QStringLiteral("Файл повреждён при скачивании: контрольная сумма не совпала с указанной на GitHub"));
        done(part);
    });
}

void AppImages::addRelease(const QVariantMap &release)
{
    const QString repo = release.value(QStringLiteral("repo")).toString();
    const QString tag = release.value(QStringLiteral("tag")).toString();
    download(QStringLiteral("@add"), release, [this, repo, tag](const QString &path) {
        install(QStringLiteral("@add"), path, true, {{QStringLiteral("github"), repo}, {QStringLiteral("tag"), tag}});
    });
}

void AppImages::update(const QString &id)
{
    const QVariantMap e = m_state.value(id).toMap();
    const QVariantMap latest = e.value(QStringLiteral("latest")).toMap();
    if (latest.isEmpty() || m_downloads.contains(id))
        return;
    const QString github = e.value(QStringLiteral("github")).toString();
    download(id, latest, [this, id, github, latest](const QString &path) {
        install(id, path, true, {{QStringLiteral("id"), id}, {QStringLiteral("github"), github}, {QStringLiteral("tag"), latest.value(QStringLiteral("tag"))}});
    });
}

void AppImages::setGitHub(const QString &id, const QString &text)
{
    if (!m_state.contains(id))
        return;
    QVariantMap e = m_state.value(id).toMap();
    e.insert(QStringLiteral("github"), parseRepo(text));
    e.remove(QStringLiteral("tag"));
    e.remove(QStringLiteral("latest"));
    e.remove(QStringLiteral("pattern"));
    m_state.insert(id, e);
    save();
    rebuild();
    if (!parseRepo(text).isEmpty())
        checkOne(id);
}

void AppImages::checkUpdates(bool force)
{
    const qint64 now = QDateTime::currentSecsSinceEpoch();
    if (!force && now - m_state.value(QStringLiteral("@lastCheck")).toLongLong() < checkEvery)
        return;
    m_state.insert(QStringLiteral("@lastCheck"), now);
    save();
    for (auto it = m_state.cbegin(); it != m_state.cend(); ++it)
        if (!it.key().startsWith(u'@') && !it.value().toMap().value(QStringLiteral("github")).toString().isEmpty())
            checkOne(it.key());
}

void AppImages::checkOne(const QString &id)
{
    const QString github = m_state.value(id).toMap().value(QStringLiteral("github")).toString();
    if (github.isEmpty())
        return;
    ++m_checking;
    Q_EMIT listChanged();
    apiGet(QStringLiteral("/repos/%1/releases/latest").arg(github), [this, id](const QVariantMap &release, const QString &error) {
        --m_checking;
        QVariantMap e = m_state.value(id).toMap();
        if (e.isEmpty() || !error.isEmpty()) {
            if (!error.isEmpty() && !e.isEmpty()) {
                e.insert(QStringLiteral("checkError"), error);
                m_state.insert(id, e);
            }
            rebuild();
            return;
        }
        e.remove(QStringLiteral("checkError"));
        const QVariantMap asset = pickAsset(release, e.value(QStringLiteral("pattern")).toString());
        const QString tag = release.value(QStringLiteral("tag_name")).toString();
        QString known = e.value(QStringLiteral("tag")).toString();
        if (known.isEmpty() && !asset.isEmpty()) {
            // Файл добавили сами: тот же ли это выпуск? По размеру или
            // по версии в названии выпуска.
            const QString version = e.value(QStringLiteral("version")).toString();
            QString bare = tag;
            if (bare.startsWith(u'v') || bare.startsWith(u'V'))
                bare = bare.mid(1);
            if (asset.value(QStringLiteral("size")).toLongLong() == e.value(QStringLiteral("size")).toLongLong()
                || (!version.isEmpty() && (bare == version || bare.endsWith(u'-' + version)))) {
                known = tag;
                e.insert(QStringLiteral("tag"), tag);
            }
        }
        // Выпуск «continuous» и подобные перезаливают под тем же тегом —
        // тогда новый файл видно по размеру.
        const bool rebuilt = tag == known && asset.value(QStringLiteral("size")).toLongLong() != e.value(QStringLiteral("size")).toLongLong();
        if (asset.isEmpty() || (tag == known && !rebuilt))
            e.remove(QStringLiteral("latest"));
        else
            e.insert(QStringLiteral("latest"), asset);
        m_state.insert(id, e);
        save();
        rebuild();
    });
}
