#include "catalog.h"
#include "flatpakops.h"
#include "textmatch.h"

#include <AppStreamQt/bundle.h>
#include <AppStreamQt/component.h>
#include <AppStreamQt/developer.h>
#include <AppStreamQt/icon.h>
#include <AppStreamQt/image.h>
#include <AppStreamQt/launchable.h>
#include <AppStreamQt/pool.h>
#include <AppStreamQt/release-list.h>
#include <AppStreamQt/release.h>
#include <AppStreamQt/screenshot.h>

#include <KService>
#include <KShell>

#include <KSycoca>

#include <QCoreApplication>
#include <QDir>
#include <QProcess>
#include <QLocale>
#include <QPointer>
#include <QSet>
#include <QThread>
#include <QUrl>

#include <algorithm>
#include <optional>
#include <malloc.h>

#include <appstream.h>
#include <alpm.h>

using AppStream::Component;
using AppStream::Pool;

namespace
{
struct CategoryInfo {
    QString key;
    QString title;
    QString icon;
    QStringList also; // подкатегории, которые тоже сюда
};

const QList<CategoryInfo> &categoryList()
{
    static const QList<CategoryInfo> list = {
        {QStringLiteral("Network"), QStringLiteral("Интернет"), QStringLiteral("applications-internet"), {}},
        {QStringLiteral("Office"), QStringLiteral("Офис"), QStringLiteral("applications-office"), {}},
        {QStringLiteral("Graphics"), QStringLiteral("Графика"), QStringLiteral("applications-graphics"), {}},
        {QStringLiteral("AudioVideo"), QStringLiteral("Музыка и видео"), QStringLiteral("applications-multimedia"),
         {QStringLiteral("Audio"), QStringLiteral("Video")}},
        {QStringLiteral("Game"), QStringLiteral("Игры"), QStringLiteral("applications-games"), {}},
        {QStringLiteral("Development"), QStringLiteral("Разработка"), QStringLiteral("applications-development"), {}},
        {QStringLiteral("Education"), QStringLiteral("Образование"), QStringLiteral("applications-education"), {}},
        {QStringLiteral("Science"), QStringLiteral("Наука"), QStringLiteral("applications-science"), {}},
        {QStringLiteral("Utility"), QStringLiteral("Инструменты"), QStringLiteral("applications-utilities"), {}},
        {QStringLiteral("System"), QStringLiteral("Система"), QStringLiteral("applications-system"), {}},
    };
    return list;
}

// Подборка на главной — известные программы, которые обычно ищут первыми.
// Ключи — id строчными (как Catalog::Entry::key).
const QStringList &curatedList()
{
    static const QStringList list = {
        QStringLiteral("org.mozilla.firefox"),
        QStringLiteral("org.telegram.desktop"),
        QStringLiteral("org.videolan.vlc"),
        QStringLiteral("org.libreoffice.libreoffice"),
        QStringLiteral("com.valvesoftware.steam"),
        QStringLiteral("com.discordapp.discord"),
        QStringLiteral("org.gimp.gimp"),
        QStringLiteral("com.obsproject.studio"),
        QStringLiteral("org.onlyoffice.desktopeditors"),
        QStringLiteral("org.qbittorrent.qbittorrent"),
        QStringLiteral("org.kde.krita"),
        QStringLiteral("com.spotify.client"),
        QStringLiteral("org.inkscape.inkscape"),
        QStringLiteral("org.kde.kdenlive"),
        QStringLiteral("md.obsidian.obsidian"),
        QStringLiteral("com.visualstudio.code"),
        QStringLiteral("org.audacityteam.audacity"),
        QStringLiteral("org.blender.blender"),
        QStringLiteral("org.chromium.chromium"),
        QStringLiteral("ru.yandex.browser"),
        QStringLiteral("net.thunderbird.thunderbird"),
        QStringLiteral("org.mozilla.thunderbird"),
        QStringLiteral("net.lutris.lutris"),
        QStringLiteral("com.heroicgameslauncher.hgl"),
        QStringLiteral("org.prismlauncher.prismlauncher"),
        QStringLiteral("com.usebottles.bottles"),
        QStringLiteral("org.signal.signal"),
        QStringLiteral("io.mpv.mpv"),
        QStringLiteral("org.keepassxc.keepassxc"),
        QStringLiteral("org.shotcut.shotcut"),
        QStringLiteral("org.darktable.darktable"),
        QStringLiteral("org.localsend.localsend_app"),
        QStringLiteral("com.github.tchx84.flatseal"),
        QStringLiteral("com.rustdesk.rustdesk"),
    };
    return list;
}

// Хвост id, по которому тоже ищут (org.kde.kdenlive → kdenlive), — кроме
// общих слов: «desktop» в org.telegram.desktop искать не должно.
const QSet<QString> &idStopWords()
{
    static const QSet<QString> set = {QStringLiteral("desktop"), QStringLiteral("client"), QStringLiteral("app"),
                                      QStringLiteral("application"), QStringLiteral("studio"), QStringLiteral("browser"),
                                      QStringLiteral("hgl")};
    return set;
}

QString keyOf(const QString &id)
{
    QString key = id.toLower();
    if (key.endsWith(QLatin1String(".desktop")))
        key.chop(8);
    return key;
}

bool hasTranslation(GHashTable *table, const QString &locale)
{
    if (!table)
        return false;
    const QByteArray lang = locale.left(2).toUtf8();
    GHashTableIter it;
    gpointer key;
    g_hash_table_iter_init(&it, table);
    while (g_hash_table_iter_next(&it, &key, nullptr)) {
        if (qstrncmp(static_cast<const char *>(key), lang.constData(), 2) == 0)
            return true;
    }
    return false;
}

QString untranslatedName(const Component &component)
{
    GHashTable *table = as_component_get_name_table(component.cPtr());
    if (!table)
        return {};
    return QString::fromUtf8(static_cast<const char *>(g_hash_table_lookup(table, "C")));
}

// Значок плитки: сохранённый на диске (128, потом 64 точки), иначе по
// сети, иначе из темы.
QString iconOf(const Component &component)
{
    QString cached;
    int cachedSize = 0;
    QString remote;
    QString stock;
    for (const AppStream::Icon &icon : component.icons()) {
        switch (icon.kind()) {
        case AppStream::Icon::KindCached:
        case AppStream::Icon::KindLocal: {
            const int size = icon.width();
            const bool better = cached.isEmpty() || (cachedSize < 128 ? size > cachedSize : (size >= 128 && size < cachedSize));
            if (better && icon.url().isLocalFile()) {
                cached = icon.url().toString();
                cachedSize = size;
            }
            break;
        }
        case AppStream::Icon::KindRemote:
            if (remote.isEmpty() || icon.width() == 128)
                remote = icon.url().toString();
            break;
        case AppStream::Icon::KindStock:
            stock = QStringLiteral("image://icon/") + icon.name();
            break;
        default:
            break;
        }
    }
    return !cached.isEmpty() ? cached : !remote.isEmpty() ? remote : stock;
}

QString homepageHost(const Component &component)
{
    QString host = component.url(Component::UrlKindHomepage).host().toLower();
    if (host.startsWith(QLatin1String("www.")))
        host = host.mid(4);
    return host;
}

void addNormalized(QStringList &list, const QStringList &values)
{
    for (const QString &value : values) {
        const QString n = TextMatch::normalize(value);
        if (!n.isEmpty() && !list.contains(n))
            list << n;
    }
}

Catalog::Entry entryFrom(const Component &component, bool flatpak, const QString &locale)
{
    Catalog::Entry e;
    e.key = keyOf(component.id());
    e.name = component.name();
    e.summary = component.summary();
    e.icon = iconOf(component);
    e.developer = component.developer().name();
    e.categories = component.categories();
    e.russian = hasTranslation(as_component_get_summary_table(component.cPtr()), locale);
    e.screenshots = int(component.screenshotsAll().size());
    if (flatpak) {
        e.flatpakId = component.id();
        e.flatpakOrigin = component.origin();
        e.verified = component.customValue(QStringLiteral("flathub::verification::verified")) == QLatin1String("true");
        for (const AppStream::Bundle &bundle : component.bundles()) {
            if (bundle.kind() == AppStream::Bundle::KindFlatpak) {
                e.flatpakRef = bundle.id();
                break;
            }
        }
    } else {
        e.archId = component.id();
        e.package = component.packageNames().value(0);
    }
    const QString desktop = component.launchable(AppStream::Launchable::KindDesktopId).entries().value(0);
    (flatpak ? e.flatpakDesktop : e.archDesktop) = desktop;
    const QString nameC = untranslatedName(component);
    e.nName = TextMatch::normalize(e.name);
    e.nNameC = TextMatch::normalize(nameC.isEmpty() ? e.name : nameC);
    e.nSummary = TextMatch::normalize(e.summary);
    e.nDeveloper = TextMatch::normalize(e.developer);
    addNormalized(e.nKeywords, component.keywords());
    return e;
}

// Вторая половина той же программы из другого источника.
void merge(Catalog::Entry &into, const Catalog::Entry &from)
{
    const bool fromIsFlatpak = !from.flatpakId.isEmpty();
    if (fromIsFlatpak) {
        into.flatpakId = from.flatpakId;
        into.flatpakRef = from.flatpakRef;
        into.flatpakOrigin = from.flatpakOrigin;
        into.flatpakDesktop = from.flatpakDesktop;
        into.verified = from.verified;
    } else {
        into.archId = from.archId;
        into.package = from.package;
        into.archDesktop = from.archDesktop;
    }
    // Описание — переведённое; при равенстве — Flathub (там полнее).
    if ((from.russian && !into.russian) || (from.russian == into.russian && fromIsFlatpak)) {
        into.name = from.name;
        into.summary = from.summary;
        into.nName = from.nName;
        into.nSummary = from.nSummary;
        into.russian = from.russian;
    }
    // Значок Flathub — PNG: открывается быстрее JPEG XL из каталога Arch.
    if (into.icon.isEmpty() || (fromIsFlatpak && from.icon.startsWith(QLatin1String("file:"))))
        into.icon = from.icon;
    if (into.developer.isEmpty())
        into.developer = from.developer, into.nDeveloper = from.nDeveloper;
    for (const QString &category : from.categories) {
        if (!into.categories.contains(category))
            into.categories << category;
    }
    into.screenshots = qMax(into.screenshots, from.screenshots);
    for (const QString &keyword : from.nKeywords) {
        if (!into.nKeywords.contains(keyword))
            into.nKeywords << keyword;
    }
}

void finishSearchFields(Catalog::Entry &e)
{
    e.nNameWords = TextMatch::words(e.nName);
    for (const QString &word : TextMatch::words(e.nNameC)) {
        if (!e.nNameWords.contains(word))
            e.nNameWords << word;
    }
    e.nIds.clear();
    if (!e.package.isEmpty())
        e.nIds << e.package.toLower();
    for (const QString &id : {e.archId, e.flatpakId}) {
        const QString key = keyOf(id);
        if (key.isEmpty())
            continue;
        const QString tail = key.section(u'.', -1);
        if (tail.size() >= 3 && !idStopWords().contains(tail) && !e.nIds.contains(tail))
            e.nIds << tail;
    }
}

// AppStream: <p>, <ul>/<ol>/<li>, <em>, <code>. Text.StyledText в QML
// понимает всё, кроме em и code.
QString styledDescription(QString markup)
{
    markup.replace(QLatin1String("<em>"), QLatin1String("<i>"));
    markup.replace(QLatin1String("</em>"), QLatin1String("</i>"));
    markup.remove(QLatin1String("<code>"));
    markup.remove(QLatin1String("</code>"));
    return markup.trimmed();
}

QVariantList screenshotsOf(const Component &component)
{
    QVariantList list;
    for (const AppStream::Screenshot &shot : component.screenshotsAll()) {
        if (shot.mediaKind() != AppStream::Screenshot::MediaKindImage)
            continue;
        QString source;
        QString thumb;
        int thumbWidth = 0;
        int sourceWidth = 0;
        int sourceHeight = 0;
        for (const AppStream::Image &image : shot.images()) {
            if (image.kind() == AppStream::Image::KindSource) {
                source = image.url().toString();
                sourceWidth = image.width();
                sourceHeight = image.height();
                continue;
            }
            // Для ленты — около 750 точек в ширину (на HiDPI — не меньше 600).
            const int w = image.width();
            if (w >= 600 && w <= 1300 && (thumb.isEmpty() || qAbs(w - 752) < qAbs(thumbWidth - 752))) {
                thumb = image.url().toString();
                thumbWidth = w;
            }
        }
        if (source.isEmpty())
            source = thumb;
        if (source.isEmpty())
            continue;
        list << QVariantMap{{QStringLiteral("thumb"), thumb.isEmpty() ? source : thumb},
                            {QStringLiteral("full"), source},
                            {QStringLiteral("width"), sourceWidth},
                            {QStringLiteral("height"), sourceHeight},
                            {QStringLiteral("caption"), shot.caption()}};
    }
    return list;
}

QString licenseText(const QString &spdx)
{
    if (spdx.isEmpty())
        return {};
    if (spdx.contains(QLatin1String("LicenseRef-proprietary")))
        return QStringLiteral("Несвободная");
    return spdx;
}
} // namespace

struct Catalog::Loaded {
    std::unique_ptr<Pool> arch;
    std::unique_ptr<Pool> flatpak;
    QList<Entry> entries;
    QHash<QString, qsizetype> byKey;
};

namespace
{
Catalog *s_catalog = nullptr;
}

Catalog *Catalog::instance()
{
    return s_catalog;
}

Catalog::Catalog(QObject *parent)
    : QObject(parent)
{
    s_catalog = this;
    connect(&m_packages, &Packages::changed, this, [this] {
        // Базы синхронизации сменились (обновили систему) — перечитать
        // описания пакетов.
        if (m_packages.hasSync() && m_pkgIndexFor != m_packages.sync().size())
            loadPackageIndex();
        ++m_revision;
        Q_EMIT revisionChanged();
    });
    load();
}

Catalog::~Catalog()
{
    if (s_catalog == this)
        s_catalog = nullptr;
}

void Catalog::load()
{
    QPointer<Catalog> self(this);
    const QString locale = QLocale::system().name();
    QThread *thread = QThread::create([self, locale] {
        auto *loaded = new Loaded;
        QThread *main = QCoreApplication::instance()->thread();
        // Flathub не подключён — подключить (без сети: только настройка).
        const QString flathubError = FlatpakOps::ensureFlathub();
        if (!flathubError.isEmpty())
            qWarning("Flathub не подключён: %s", qPrintable(flathubError));

        loaded->arch = std::make_unique<Pool>();
        loaded->arch->setLocale(locale);
        loaded->arch->setFlags(Pool::FlagLoadOsCatalog);
        if (!loaded->arch->load())
            qWarning("Каталог Arch не загрузился: %s", qPrintable(loaded->arch->lastError()));
        loaded->flatpak = std::make_unique<Pool>();
        loaded->flatpak->setLocale(locale);
        loaded->flatpak->setFlags(Pool::FlagLoadFlatpak);
        if (!loaded->flatpak->load())
            qWarning("Каталог Flathub не загрузился: %s", qPrintable(loaded->flatpak->lastError()));

        QList<Entry> &entries = loaded->entries;
        QHash<QString, qsizetype> &byKey = loaded->byKey;
        QList<QString> hosts;
        QList<bool> dead;
        auto add = [&](const Entry &e, const QString &host) {
            byKey.insert(e.key, entries.size());
            entries << e;
            hosts << host;
            dead << false;
        };
        for (const Component &c : loaded->arch->componentsByKind(Component::KindDesktopApp).toList()) {
            Entry e = entryFrom(c, false, locale);
            if (e.package.isEmpty() || byKey.contains(e.key))
                continue;
            add(e, homepageHost(c));
        }
        const qsizetype archCount = entries.size();
        for (const Component &c : loaded->flatpak->componentsByKind(Component::KindDesktopApp).toList()) {
            Entry e = entryFrom(c, true, locale);
            if (e.flatpakRef.isEmpty())
                continue;
            const auto it = byKey.constFind(e.key);
            if (it == byKey.constEnd()) {
                add(e, homepageHost(c));
                continue;
            }
            Entry &other = entries[*it];
            if (other.flatpakId.isEmpty())
                merge(other, e);
        }

        // Та же программа под разными id (discord.desktop и
        // com.discordapp.Discord): то же имя и тот же сайт или разработчик.
        QHash<QString, QList<qsizetype>> flatpakByName;
        for (qsizetype i = archCount; i < entries.size(); ++i)
            flatpakByName[entries[i].nNameC].append(i);
        for (qsizetype i = 0; i < archCount; ++i) {
            Entry &arch = entries[i];
            if (!arch.flatpakId.isEmpty())
                continue;
            const QList<qsizetype> candidates = flatpakByName.value(arch.nNameC);
            for (qsizetype j : candidates) {
                Entry &flat = entries[j];
                if (dead[j] || !flat.archId.isEmpty())
                    continue;
                const bool sameSite = !hosts[i].isEmpty() && hosts[i] == hosts[j];
                const bool sameDeveloper = !arch.nDeveloper.isEmpty() && arch.nDeveloper == flat.nDeveloper;
                // Пакет назван как программа: discord ↔ com.discordapp.Discord,
                // libreoffice-fresh ↔ org.libreoffice.LibreOffice.
                const QString tail = keyOf(flat.flatpakId).section(u'.', -1);
                const QString package = arch.package.toLower();
                const bool samePackage = tail.size() >= 3 && (package == tail || package.startsWith(tail + u'-'));
                if (!sameSite && !sameDeveloper && !samePackage)
                    continue;
                // В запись Flathub: её id — общепринятый.
                merge(flat, arch);
                byKey.insert(arch.key, j);
                dead[i] = true;
                break;
            }
        }

        QList<Entry> alive;
        QHash<qsizetype, qsizetype> moved;
        alive.reserve(entries.size());
        for (qsizetype i = 0; i < entries.size(); ++i) {
            if (dead[i])
                continue;
            moved.insert(i, alive.size());
            alive << entries[i];
        }
        for (auto it = byKey.begin(); it != byKey.end(); ++it)
            it.value() = moved.value(it.value(), -1);
        entries = alive;

        for (Entry &e : entries) {
            finishSearchFields(e);
            e.curated = int(curatedList().indexOf(e.key));
        }
        loaded->arch->moveToThread(main);
        loaded->flatpak->moveToThread(main);

        QMetaObject::invokeMethod(QCoreApplication::instance(), [self, loaded] {
            if (self)
                self->finishLoad(loaded);
            else
                delete loaded;
        });
    });
    connect(thread, &QThread::finished, thread, &QObject::deleteLater);
    thread->start(QThread::LowPriority);
}

void Catalog::finishLoad(Loaded *loaded)
{
    m_archPool = std::move(loaded->arch);
    m_flatpakPool = std::move(loaded->flatpak);
    m_entries = std::move(loaded->entries);
    m_byKey = std::move(loaded->byKey);
    m_catalogPackages.clear();
    for (const Entry &e : std::as_const(m_entries)) {
        if (!e.package.isEmpty())
            m_catalogPackages.insert(e.package);
    }
    delete loaded;
    m_flathub = std::any_of(m_entries.cbegin(), m_entries.cend(), [](const Entry &e) { return !e.flatpakRef.isEmpty(); });
    const bool first = !m_ready;
    m_ready = true;
    // Разбор каталога оставил в куче десятки МБ временного — вернуть системе.
    malloc_trim(0);
    if (first)
        Q_EMIT readyChanged();
    ++m_revision;
    Q_EMIT revisionChanged();
    if (!m_refreshed) {
        m_refreshed = true;
        refreshFlathub();
    }
}

void Catalog::setFlathubStatus(const QString &status)
{
    if (m_flathubStatus == status)
        return;
    m_flathubStatus = status;
    Q_EMIT flathubStatusChanged();
}

// Каталог Flathub — раз в сутки свежий (flatpak сам его не обновляет, пока
// не поставишь или обновишь что-нибудь из командной строки). Нет его
// совсем — качаем сразу и показываем, что качаем.
void Catalog::refreshFlathub()
{
    if (!m_flathub)
        setFlathubStatus(QStringLiteral("loading"));
    QPointer<Catalog> self(this);
    const qint64 maxAge = m_flathub ? 24 * 3600 : 0;
    QThread *thread = QThread::create([self, maxAge] {
        bool changed = false;
        const QString error = FlatpakOps::refreshAppstream(maxAge, &changed);
        QMetaObject::invokeMethod(QCoreApplication::instance(), [self, error, changed] {
            if (!self)
                return;
            if (changed) {
                self->load(); // перечитать с новым каталогом
                self->setFlathubStatus(QString());
                return;
            }
            self->setFlathubStatus(self->m_flathub ? QString() : error.isEmpty() ? QStringLiteral("Каталог Flathub пуст") : error);
        });
    });
    connect(thread, &QThread::finished, thread, &QObject::deleteLater);
    thread->start(QThread::LowPriority);
}

namespace
{
// Exec из .desktop без полей %f %U и прочих: файлов не передаём.
QStringList execArgs(const KService::Ptr &service)
{
    KShell::Errors error = KShell::NoError;
    const QStringList parts = KShell::splitArgs(service->exec(), KShell::NoOptions, &error);
    if (error != KShell::NoError)
        return {};
    QStringList argv;
    for (QString part : parts) {
        if (part == QLatin1String("%i")) {
            if (!service->icon().isEmpty())
                argv << QStringLiteral("--icon") << service->icon();
            continue;
        }
        if (part == QLatin1String("%c")) {
            argv << service->name();
            continue;
        }
        if (part == QLatin1String("%k")) {
            argv << service->entryPath();
            continue;
        }
        if (part.size() == 2 && part.startsWith(QLatin1Char('%')))
            continue;
        part.replace(QLatin1String("%%"), QLatin1String("%"));
        argv << part;
    }
    return argv;
}
} // namespace

QVariantMap Catalog::resolveDesktop(const QString &desktopId) const
{
    if (!m_ready)
        return {};
    QString id = desktopId.trimmed().toLower();
    if (id.endsWith(QLatin1String(".desktop")))
        id.chop(8);
    if (id.isEmpty())
        return {};
    // Обычно id компонента и есть id .desktop (org.kde.ark, flatpak).
    const auto found = [](const QString &key) { return QVariantMap{{QStringLiteral("key"), key}}; };
    if (m_byKey.contains(id))
        return found(id);
    const QString file = id + QStringLiteral(".desktop");
    for (const Entry &e : m_entries) {
        if (e.archDesktop.toLower() == file || e.flatpakDesktop.toLower() == file)
            return found(e.key);
    }
    // Иначе — чей это файл: пакет из каталога или поставленный не из
    // репозиториев (AUR).
    const KService::Ptr service = KService::serviceByDesktopName(desktopId.endsWith(QLatin1String(".desktop")) ? desktopId.chopped(8) : desktopId);
    const QString path = service ? service->entryPath() : QString();
    if (path.isEmpty() || !path.startsWith(QLatin1String("/usr/")))
        return {};
    QProcess pacman;
    pacman.start(QStringLiteral("pacman"), {QStringLiteral("-Qqo"), path});
    if (!pacman.waitForFinished(3000) || pacman.exitCode() != 0)
        return {};
    const QString package = QString::fromUtf8(pacman.readAllStandardOutput()).trimmed();
    if (package.isEmpty())
        return {};
    for (const Entry &e : m_entries) {
        if (e.package == package)
            return found(e.key);
    }
    return {{QStringLiteral("package"), package},
            {QStringLiteral("foreign"), !m_packages.sync().contains(package)},
            {QStringLiteral("name"), service->name()},
            {QStringLiteral("icon"), service->icon()}};
}

bool Catalog::launch(const QString &id, const QString &kind) const
{
    const qsizetype i = m_byKey.value(id.toLower(), -1);
    if (i < 0)
        return false;
    const Entry &e = m_entries[i];
    const bool flatpak = kind == QLatin1String("flathub");
    QString desktop = flatpak ? e.flatpakDesktop : e.archDesktop;
    if (desktop.isEmpty())
        desktop = (flatpak ? e.flatpakId : e.archId) + QStringLiteral(".desktop");
    QString desktopId = desktop;
    if (desktopId.endsWith(QLatin1String(".desktop")))
        desktopId.chop(8);
    // Как оболочка: в своей группе systemd (/usr/lib/sedmio/launch).
    const QString launcher = QStringLiteral("/usr/lib/sedmio/launch");
    if (flatpak) {
        const QString appId = e.flatpakId.endsWith(QLatin1String(".desktop")) ? e.flatpakId.chopped(8) : e.flatpakId;
        return QProcess::startDetached(launcher, {desktopId, QStringLiteral("flatpak"), QStringLiteral("run"), appId});
    }
    KSycoca::self()->ensureCacheValid();
    const KService::Ptr service = KService::serviceByStorageId(desktop);
    const QStringList argv = service ? execArgs(service) : QStringList();
    if (argv.isEmpty())
        return false;
    return QProcess::startDetached(launcher, QStringList{desktopId} + argv,
                                   service->workingDirectory().isEmpty() ? QDir::homePath() : service->workingDirectory());
}

void Catalog::checkUpdates()
{
    if (m_checkingUpdates)
        return;
    m_checkingUpdates = true;
    Q_EMIT updatesChanged();
    QPointer<Catalog> self(this);
    QThread *thread = QThread::create([self] {
        QString error;
        const QList<FlatpakOps::Update> list = FlatpakOps::updates(&error, nullptr);
        QMetaObject::invokeMethod(QCoreApplication::instance(), [self, list, error] {
            if (!self)
                return;
            QVariantList result;
            for (const FlatpakOps::Update &u : list) {
                // Среды выполнения обновятся вместе со всем («Обновить всё»),
                // в списке — только программы.
                if (u.ref.startsWith(QLatin1String("runtime/")))
                    continue;
                const qsizetype i = self->m_byKey.value(u.id.toLower(), -1);
                QVariantMap tile = i >= 0 ? self->tile(self->m_entries[i]) : QVariantMap{
                    {QStringLiteral("id"), u.id.toLower()},
                    {QStringLiteral("name"), u.name.isEmpty() ? u.id : u.name},
                    {QStringLiteral("summary"), QString()},
                    {QStringLiteral("icon"), QString()},
                };
                tile.insert(QStringLiteral("ref"), u.ref);
                result << tile;
            }
            self->m_updates = result;
            self->m_updatesError = error;
            self->m_checkingUpdates = false;
            Q_EMIT self->updatesChanged();
        });
    });
    connect(thread, &QThread::finished, thread, &QObject::deleteLater);
    thread->start(QThread::LowPriority);
}

QVariantList Catalog::categories() const
{
    QVariantList list;
    for (const CategoryInfo &info : categoryList())
        list << QVariantMap{{QStringLiteral("key"), info.key}, {QStringLiteral("title"), info.title}, {QStringLiteral("icon"), info.icon}};
    return list;
}

bool Catalog::archAvailable(const Entry &entry) const
{
    if (entry.package.isEmpty())
        return false;
    // Каталог отстаёт от баз pacman: пакета там уже (или ещё) нет — не
    // предлагаем, иначе установка упадёт на «не найден».
    return !m_packages.hasSync() || m_packages.sync().contains(entry.package);
}

bool Catalog::flathubAvailable(const Entry &entry) const
{
    return !entry.flatpakRef.isEmpty();
}

QString Catalog::installedSource(const Entry &entry) const
{
    const bool arch = !entry.package.isEmpty() && m_packages.installed().contains(entry.package);
    const bool flatpak = !entry.flatpakId.isEmpty() && m_packages.flatpaks().contains(entry.flatpakId.toLower());
    return arch && flatpak ? QStringLiteral("both") : arch ? QStringLiteral("arch") : flatpak ? QStringLiteral("flathub") : QString();
}

bool Catalog::visible(const Entry &entry) const
{
    return archAvailable(entry) || flathubAvailable(entry) || !installedSource(entry).isEmpty();
}

QVariantMap Catalog::tile(const Entry &entry) const
{
    return {
        {QStringLiteral("id"), entry.key},
        {QStringLiteral("name"), entry.name},
        {QStringLiteral("summary"), entry.summary},
        {QStringLiteral("icon"), entry.icon},
        {QStringLiteral("arch"), archAvailable(entry)},
        {QStringLiteral("flathub"), flathubAvailable(entry)},
        {QStringLiteral("installed"), installedSource(entry)},
        {QStringLiteral("verified"), entry.verified},
    };
}

int Catalog::quality(const Entry &entry) const
{
    if (entry.curated >= 0)
        return 1000 - entry.curated * 5;
    int q = 0;
    if (entry.verified)
        q += 30;
    if (archAvailable(entry) && flathubAvailable(entry))
        q += 25;
    if (entry.screenshots > 0)
        q += 20;
    if (entry.russian)
        q += 15;
    if (!entry.developer.isEmpty())
        q += 5;
    if (entry.icon.isEmpty())
        q -= 300;
    return q;
}

namespace
{
// Одно слово запроса против одной программы: 0 — не нашлось.
int wordScore(const Catalog::Entry &e, const QString &w)
{
    int best = 0;
    for (const QString &nameWord : e.nNameWords) {
        if (nameWord == w)
            best = qMax(best, 400);
        else if (nameWord.startsWith(w))
            best = qMax(best, 300);
        else if (w.size() >= 3 && nameWord.contains(w))
            best = qMax(best, 120);
    }
    for (const QString &id : e.nIds) {
        if (id == w)
            best = qMax(best, 350);
        else if (id.startsWith(w))
            best = qMax(best, 200);
    }
    if (best < 300) {
        for (const QString &keyword : e.nKeywords) {
            // Слово, которое программа сама о себе заявила («браузер»), —
            // почти как имя.
            if (keyword == w)
                best = qMax(best, 300);
            else if (keyword.startsWith(w))
                best = qMax(best, 150);
            else if (keyword.contains(u' ' + w))
                best = qMax(best, 80);
        }
    }
    if (best < 40 && (e.nSummary.startsWith(w) || e.nSummary.contains(u' ' + w)))
        best = 40;
    if (best < 30 && (e.nDeveloper.startsWith(w) || e.nDeveloper.contains(u' ' + w)))
        best = 30;
    return best;
}

// Общие слова по-русски: у многих программ ключевые слова только
// английские, а ищут «офис», «игры», «фотошоп». Слово запроса подходит, если
// начинается с основы (или сама основа начинается с набранного — «брау»).
struct Synonym {
    QStringList stems;
    QStringList english;
    QStringList categories; // freedesktop: программа из раздела — подходит
};

const QList<Synonym> &synonymList()
{
    static const QList<Synonym> list = {
        {{QStringLiteral("офис")}, {QStringLiteral("office")}, {QStringLiteral("Office")}},
        {{QStringLiteral("документ")}, {QStringLiteral("document"), QStringLiteral("office")}, {QStringLiteral("WordProcessor")}},
        {{QStringLiteral("таблиц")}, {QStringLiteral("spreadsheet")}, {QStringLiteral("Spreadsheet")}},
        {{QStringLiteral("презентац")}, {QStringLiteral("presentation")}, {QStringLiteral("Presentation")}},
        {{QStringLiteral("текст")}, {QStringLiteral("text")}, {QStringLiteral("TextEditor")}},
        {{QStringLiteral("браузер"), QStringLiteral("обозревател")}, {QStringLiteral("browser")}, {QStringLiteral("WebBrowser")}},
        {{QStringLiteral("почт")}, {QStringLiteral("mail"), QStringLiteral("email")}, {QStringLiteral("Email")}},
        {{QStringLiteral("мессенджер"), QStringLiteral("чат")}, {QStringLiteral("messenger"), QStringLiteral("chat")},
         {QStringLiteral("InstantMessaging"), QStringLiteral("Chat")}},
        {{QStringLiteral("игр")}, {QStringLiteral("game"), QStringLiteral("games")}, {QStringLiteral("Game")}},
        {{QStringLiteral("музык")}, {QStringLiteral("music")}, {QStringLiteral("Music")}},
        {{QStringLiteral("звук"), QStringLiteral("аудио")}, {QStringLiteral("audio"), QStringLiteral("sound")}, {QStringLiteral("Audio")}},
        {{QStringLiteral("видео"), QStringLiteral("фильм"), QStringLiteral("кино")}, {QStringLiteral("video"), QStringLiteral("movie")},
         {QStringLiteral("Video")}},
        {{QStringLiteral("плеер"), QStringLiteral("проигрывател")}, {QStringLiteral("player")}, {QStringLiteral("Player")}},
        {{QStringLiteral("монтаж")}, {QStringLiteral("editing")}, {QStringLiteral("AudioVideoEditing")}},
        {{QStringLiteral("фото"), QStringLiteral("снимк")}, {QStringLiteral("photo"), QStringLiteral("image")}, {QStringLiteral("Photography")}},
        {{QStringLiteral("фотошоп")}, {QStringLiteral("photoshop")}, {QStringLiteral("RasterGraphics")}},
        {{QStringLiteral("рисова"), QStringLiteral("рисунк")}, {QStringLiteral("paint"), QStringLiteral("drawing")},
         {QStringLiteral("RasterGraphics"), QStringLiteral("VectorGraphics")}},
        {{QStringLiteral("графи")}, {QStringLiteral("graphics")}, {QStringLiteral("Graphics")}},
        {{QStringLiteral("торрент")}, {QStringLiteral("torrent"), QStringLiteral("bittorrent")}, {QStringLiteral("P2P")}},
        {{QStringLiteral("парол")}, {QStringLiteral("password"), QStringLiteral("passwords")}, {}},
        {{QStringLiteral("архив")}, {QStringLiteral("archive"), QStringLiteral("zip")}, {QStringLiteral("Archiving"), QStringLiteral("Compression")}},
        {{QStringLiteral("программирован"), QStringLiteral("разработк")}, {QStringLiteral("ide"), QStringLiteral("development")},
         {QStringLiteral("Development")}},
        {{QStringLiteral("редактор")}, {QStringLiteral("editor")}, {}},
        {{QStringLiteral("калькулятор")}, {QStringLiteral("calculator")}, {QStringLiteral("Calculator")}},
        {{QStringLiteral("заметк")}, {QStringLiteral("notes"), QStringLiteral("note")}, {}},
        {{QStringLiteral("книг"), QStringLiteral("читалк")}, {QStringLiteral("ebook"), QStringLiteral("book")}, {}},
        {{QStringLiteral("эмулятор"), QStringLiteral("виртуальн")}, {QStringLiteral("emulator"), QStringLiteral("virtual")},
         {QStringLiteral("Emulator")}},
        {{QStringLiteral("удаленн")}, {QStringLiteral("remote")}, {QStringLiteral("RemoteAccess")}},
        {{QStringLiteral("загрузк"), QStringLiteral("скачива")}, {QStringLiteral("download"), QStringLiteral("downloader")}, {}},
        {{QStringLiteral("запис")}, {QStringLiteral("recorder"), QStringLiteral("recording")}, {QStringLiteral("Recorder")}},
    };
    return list;
}
} // namespace

Catalog::Word Catalog::makeWord(const QString &text)
{
    Word word{text, {}, {}};
    for (const Synonym &synonym : synonymList()) {
        const bool match = std::any_of(synonym.stems.cbegin(), synonym.stems.cend(), [&text](const QString &stem) {
            return text.startsWith(stem) || (text.size() >= 3 && stem.startsWith(text));
        });
        if (!match)
            continue;
        word.english << synonym.english;
        word.categories << synonym.categories;
    }
    return word;
}

int Catalog::score(const Entry &e, const QList<Word> &words, const QString &whole) const
{
    int total = 0;
    for (const Word &word : words) {
        int best = wordScore(e, word.text);
        for (const QString &english : word.english)
            best = qMax(best, wordScore(e, english) * 4 / 5);
        // «игры» — любая игра, «офис» — любая офисная программа.
        if (best < 250 && std::any_of(word.categories.cbegin(), word.categories.cend(), [&e](const QString &c) {
                return e.categories.contains(c);
            }))
            best = 250;
        if (best == 0)
            return -1;
        total += best;
    }
    if (e.nName == whole || e.nNameC == whole) {
        total += 1000;
    } else {
        // Начало имени: тем весомее, чем больше имени набрано («браузер» в
        // «Браузер journald» — меньше половины).
        for (const QString &name : {e.nName, e.nNameC}) {
            if (name.startsWith(whole)) {
                total += 500 * whole.size() / name.size();
                break;
            }
        }
    }
    // Подборка — то, что ищут чаще всего: на общее слово («браузер») первым
    // должен выйти Firefox, а не программа с этим словом в имени.
    return total + (e.curated >= 0 ? 400 : quality(e) / 4);
}

QVariantList Catalog::search(const QString &text, int limit) const
{
    QVariantList result;
    if (!m_ready)
        return result;
    const QString query = TextMatch::normalize(text);
    if (query.isEmpty())
        return result;

    // Как набрано; в другой раскладке; латиницей. Догадки — только если
    // совпало имя или id: иначе «мдс» (vlc по-русски) насобирает мусора.
    auto toWords = [](const QString &normalized) {
        QList<Word> list;
        for (const QString &w : TextMatch::words(normalized))
            list << makeWord(w);
        return list;
    };
    struct Variant {
        QString whole;
        QList<Word> words;
        int penalty;
        int minimum;
    };
    QList<Variant> variants = {{query, toWords(query), 0, 0}};
    const QString swapped = TextMatch::swapLayout(query);
    if (!swapped.isEmpty())
        variants << Variant{swapped, toWords(swapped), 50, 300};
    const QString latin = TextMatch::transliterate(query);
    if (!latin.isEmpty())
        variants << Variant{latin, toWords(latin), 80, 300};

    QList<std::pair<int, qsizetype>> hits;
    QSet<qsizetype> seen;
    for (qsizetype i = 0; i < m_entries.size(); ++i) {
        const Entry &e = m_entries[i];
        int best = -1;
        for (const Variant &v : variants) {
            const int s = score(e, v.words, v.whole);
            if (s >= 0 && s >= v.minimum)
                best = qMax(best, s - v.penalty);
        }
        if (best < 0 || !visible(e))
            continue;
        hits.append({best, i});
        seen.insert(i);
    }

    // Мало нашли — добираем поиском AppStream: он смотрит и в описание
    // («редактор фото» найдёт GIMP по словам из описания).
    // Только когда своих нет совсем: AppStream ищет медленнее (до 0,1 с) и
    // находит по словам из описания — рядом с точным совпадением это шум.
    if (hits.isEmpty()) {
        for (Pool *pool : {m_archPool.get(), m_flatpakPool.get()}) {
            if (!pool)
                continue;
            int taken = 0;
            for (const Component &c : pool->search(text).toList()) {
                if (c.kind() != Component::KindDesktopApp)
                    continue;
                const qsizetype i = m_byKey.value(keyOf(c.id()), -1);
                if (i < 0 || seen.contains(i) || !visible(m_entries[i]))
                    continue;
                seen.insert(i);
                hits.append({10 + quality(m_entries[i]) / 10 - taken, i});
                if (++taken >= 20)
                    break;
            }
        }
    }

    std::sort(hits.begin(), hits.end(), [this](const auto &a, const auto &b) {
        if (a.first != b.first)
            return a.first > b.first;
        return m_entries[a.second].name.localeAwareCompare(m_entries[b.second].name) < 0;
    });
    for (qsizetype k = 0; k < hits.size() && k < limit; ++k)
        result << tile(m_entries[hits[k].second]);
    return result;
}

QVariantList Catalog::featured() const
{
    QVariantList result;
    if (!m_ready)
        return result;
    for (const QString &key : curatedList()) {
        const qsizetype i = m_byKey.value(key, -1);
        if (i < 0 || !visible(m_entries[i]))
            continue;
        // Thunderbird в Arch и на Flathub — под разными id; второй раз не
        // показываем.
        bool duplicate = false;
        for (const QVariant &v : std::as_const(result))
            duplicate = duplicate || v.toMap().value(QStringLiteral("id")) == m_entries[i].key;
        if (!duplicate)
            result << tile(m_entries[i]);
    }
    return result;
}

QVariantList Catalog::category(const QString &key, int limit) const
{
    QVariantList result;
    if (!m_ready)
        return result;
    QStringList keys = {key};
    for (const CategoryInfo &info : categoryList()) {
        if (info.key == key)
            keys << info.also;
    }
    QList<std::pair<int, qsizetype>> hits;
    for (qsizetype i = 0; i < m_entries.size(); ++i) {
        const Entry &e = m_entries[i];
        const bool match = std::any_of(keys.cbegin(), keys.cend(), [&e](const QString &k) { return e.categories.contains(k); });
        if (match && visible(e))
            hits.append({quality(e), i});
    }
    std::sort(hits.begin(), hits.end(), [this](const auto &a, const auto &b) {
        if (a.first != b.first)
            return a.first > b.first;
        return m_entries[a.second].name.localeAwareCompare(m_entries[b.second].name) < 0;
    });
    for (qsizetype k = 0; k < hits.size() && k < limit; ++k)
        result << tile(m_entries[hits[k].second]);
    return result;
}

QVariantList Catalog::installedApps() const
{
    QList<qsizetype> found;
    for (qsizetype i = 0; i < m_entries.size(); ++i) {
        if (!installedSource(m_entries[i]).isEmpty())
            found << i;
    }
    std::sort(found.begin(), found.end(), [this](qsizetype a, qsizetype b) {
        return m_entries[a].name.localeAwareCompare(m_entries[b].name) < 0;
    });
    QVariantList result;
    for (qsizetype i : found)
        result << tile(m_entries[i]);
    return result;
}

QVariantMap Catalog::details(const QString &id) const
{
    if (id.startsWith(QLatin1String("pkg:")))
        return m_ready ? packageDetails(id.mid(4)) : QVariantMap();
    const qsizetype i = m_byKey.value(id.toLower(), -1);
    if (!m_ready || i < 0)
        return {};
    const Entry &e = m_entries[i];
    auto first = [](Pool *pool, const QString &cid) -> Component {
        if (!pool || cid.isEmpty())
            return Component();
        const QList<Component> list = pool->componentsById(cid).toList();
        return list.isEmpty() ? Component() : list.constFirst();
    };
    const Component arch = first(m_archPool.get(), e.archId);
    const Component flatpak = first(m_flatpakPool.get(), e.flatpakId);
    const bool haveArch = !e.archId.isEmpty() && !arch.id().isEmpty();
    const bool haveFlatpak = !e.flatpakId.isEmpty() && !flatpak.id().isEmpty();
    // Описание — переведённое; при равенстве — Flathub.
    const QString locale = QLocale::system().name();
    const bool archRussian = haveArch && hasTranslation(as_component_get_summary_table(arch.cPtr()), locale);
    const bool flatpakRussian = haveFlatpak && hasTranslation(as_component_get_summary_table(flatpak.cPtr()), locale);
    const Component &main = haveFlatpak && (flatpakRussian || !archRussian) ? flatpak : arch;
    const Component &other = &main == &flatpak ? arch : flatpak;
    const bool haveOther = &main == &flatpak ? haveArch : haveFlatpak;

    QString description = main.description();
    if (description.isEmpty() && haveOther)
        description = other.description();
    QVariantList shots = screenshotsOf(main);
    if (shots.isEmpty() && haveOther)
        shots = screenshotsOf(other);
    QUrl homepage = main.url(Component::UrlKindHomepage);
    if (homepage.isEmpty() && haveOther)
        homepage = other.url(Component::UrlKindHomepage);

    QVariantList sources;
    if (!e.package.isEmpty()) {
        const QString installedVersion = m_packages.installed().value(e.package);
        sources << QVariantMap{
            {QStringLiteral("kind"), QStringLiteral("arch")},
            {QStringLiteral("available"), archAvailable(e)},
            {QStringLiteral("package"), e.package},
            {QStringLiteral("repo"), m_packages.repo(e.package)},
            {QStringLiteral("version"), m_packages.sync().value(e.package)},
            {QStringLiteral("installed"), !installedVersion.isEmpty()},
            {QStringLiteral("installedVersion"), installedVersion},
        };
    }
    if (!e.flatpakRef.isEmpty()) {
        std::optional<AppStream::Release> release;
        if (haveFlatpak)
            release = flatpak.releasesPlain().indexSafe(0);
        const Packages::Flatpak installed = m_packages.flatpaks().value(e.flatpakId.toLower());
        sources << QVariantMap{
            {QStringLiteral("kind"), QStringLiteral("flathub")},
            {QStringLiteral("available"), true},
            {QStringLiteral("ref"), e.flatpakRef},
            {QStringLiteral("origin"), e.flatpakOrigin},
            {QStringLiteral("version"), release ? release->version() : QString()},
            {QStringLiteral("verified"), e.verified},
            {QStringLiteral("installed"), !installed.id.isEmpty()},
            {QStringLiteral("installedVersion"), installed.version},
            {QStringLiteral("userInstall"), installed.user},
        };
    }

    QStringList categoryTitles;
    for (const CategoryInfo &info : categoryList()) {
        const bool match = e.categories.contains(info.key)
            || std::any_of(info.also.cbegin(), info.also.cend(), [&e](const QString &k) { return e.categories.contains(k); });
        if (match)
            categoryTitles << info.title;
    }

    return {
        {QStringLiteral("id"), e.key},
        {QStringLiteral("name"), e.name},
        {QStringLiteral("summary"), e.summary},
        {QStringLiteral("icon"), e.icon},
        {QStringLiteral("developer"), e.developer},
        {QStringLiteral("verified"), e.verified},
        {QStringLiteral("description"), styledDescription(description)},
        {QStringLiteral("screenshots"), shots},
        {QStringLiteral("homepage"), homepage.toString()},
        {QStringLiteral("license"), licenseText(main.projectLicense())},
        {QStringLiteral("categories"), categoryTitles},
        {QStringLiteral("sources"), sources},
        {QStringLiteral("installed"), installedSource(e)},
    };
}

// ---- Пакеты без карточки

void Catalog::loadPackageIndex()
{
    if (m_pkgIndexLoading)
        return;
    m_pkgIndexLoading = true;
    const int forSize = int(m_packages.sync().size());
    QPointer<Catalog> self(this);
    // libalpm читает базы сам (около 0,2 с на 15 000 пакетов) — в потоке.
    QThread *thread = QThread::create([self, forSize] {
        QProcess conf;
        conf.start(QStringLiteral("pacman-conf"), {QStringLiteral("--repo-list")});
        conf.waitForFinished(5000);
        const QStringList repos = QString::fromUtf8(conf.readAllStandardOutput()).split(u'\n', Qt::SkipEmptyParts);
        auto *index = new QHash<QString, PkgInfo>;
        alpm_errno_t err;
        alpm_handle_t *handle = alpm_initialize("/", "/var/lib/pacman/", &err);
        if (handle) {
            for (const QString &repo : repos) {
                alpm_db_t *db = alpm_register_syncdb(handle, repo.toUtf8().constData(), 0);
                if (!db)
                    continue;
                for (alpm_list_t *i = alpm_db_get_pkgcache(db); i; i = alpm_list_next(i)) {
                    auto *pkg = static_cast<alpm_pkg_t *>(i->data);
                    const QString name = QString::fromUtf8(alpm_pkg_get_name(pkg));
                    if (index->contains(name))
                        continue; // первый репозиторий главный, как у pacman
                    PkgInfo info;
                    info.name = name;
                    info.desc = QString::fromUtf8(alpm_pkg_get_desc(pkg));
                    info.url = QString::fromUtf8(alpm_pkg_get_url(pkg));
                    QStringList licenses;
                    for (alpm_list_t *l = alpm_pkg_get_licenses(pkg); l; l = alpm_list_next(l))
                        licenses << QString::fromUtf8(static_cast<const char *>(l->data));
                    info.licenses = licenses.join(QStringLiteral(", "));
                    info.installedSize = alpm_pkg_get_isize(pkg);
                    info.nName = TextMatch::normalize(name);
                    info.nDesc = TextMatch::normalize(info.desc);
                    index->insert(name, info);
                }
            }
            alpm_release(handle);
        }
        QMetaObject::invokeMethod(QCoreApplication::instance(), [self, index, forSize] {
            if (self) {
                self->m_pkgInfo = std::move(*index);
                self->m_pkgIndexFor = forSize;
                self->m_pkgIndexLoading = false;
                ++self->m_revision;
                Q_EMIT self->revisionChanged();
            }
            delete index;
        });
    });
    connect(thread, &QThread::finished, thread, &QObject::deleteLater);
    thread->start();
}

QVariantList Catalog::searchPackages(const QString &text, int limit) const
{
    QVariantList result;
    const QString query = TextMatch::normalize(text);
    if (query.size() < 2 || m_pkgInfo.isEmpty())
        return result;
    // Набрано не в той раскладке («рещз» — htop).
    QStringList variants{query};
    const QString swapped = TextMatch::swapLayout(query);
    if (!swapped.isEmpty())
        variants << swapped;
    const QStringList words = TextMatch::words(query);
    QList<std::pair<int, const PkgInfo *>> hits;
    for (auto it = m_pkgInfo.cbegin(); it != m_pkgInfo.cend(); ++it) {
        const PkgInfo &p = it.value();
        if (m_catalogPackages.contains(p.name))
            continue;
        int best = 0;
        for (const QString &q : std::as_const(variants)) {
            if (p.nName == q)
                best = qMax(best, 1000);
            else if (p.nName.startsWith(q))
                best = qMax(best, 800 - int(p.nName.size() - q.size()));
            else if (q.size() >= 3 && p.nName.contains(q))
                best = qMax(best, 500 - int(p.nName.size() - q.size()));
        }
        // Все слова запроса — в описании.
        if (best == 0 && !words.isEmpty() && words.constFirst().size() >= 3
            && std::all_of(words.cbegin(), words.cend(), [&p](const QString &w) { return p.nDesc.contains(w); }))
            best = 200;
        if (best == 0)
            continue;
        // Установленное и не библиотеки — выше.
        if (m_packages.installed().contains(p.name))
            best += 30;
        if (p.name.startsWith(QLatin1String("lib")) || p.name.startsWith(QLatin1String("python-")) || p.name.startsWith(QLatin1String("perl-"))
            || p.name.startsWith(QLatin1String("haskell-")) || p.name.startsWith(QLatin1String("ruby-")) || p.name.startsWith(QLatin1String("lib32-")))
            best -= 100;
        hits.append({best, &p});
    }
    std::sort(hits.begin(), hits.end(), [](const auto &a, const auto &b) {
        return a.first != b.first ? a.first > b.first : a.second->name < b.second->name;
    });
    for (qsizetype i = 0; i < hits.size() && i < limit; ++i) {
        const PkgInfo &p = *hits.at(i).second;
        result << QVariantMap{{QStringLiteral("id"), QStringLiteral("pkg:") + p.name},
                              {QStringLiteral("name"), p.name},
                              {QStringLiteral("summary"), p.desc},
                              {QStringLiteral("version"), m_packages.sync().value(p.name)},
                              {QStringLiteral("repo"), m_packages.repo(p.name)},
                              {QStringLiteral("installed"), m_packages.installed().contains(p.name)}};
    }
    return result;
}

QVariantMap Catalog::packageDetails(const QString &name) const
{
    const bool known = m_pkgInfo.contains(name);
    const QString installedVersion = m_packages.installed().value(name);
    if (!known && installedVersion.isEmpty())
        return {};
    const PkgInfo p = m_pkgInfo.value(name);
    QVariantList sources{QVariantMap{
        {QStringLiteral("kind"), QStringLiteral("arch")},
        {QStringLiteral("available"), m_packages.sync().contains(name)},
        {QStringLiteral("package"), name},
        {QStringLiteral("repo"), m_packages.repo(name)},
        {QStringLiteral("version"), m_packages.sync().value(name)},
        {QStringLiteral("installed"), !installedVersion.isEmpty()},
        {QStringLiteral("installedVersion"), installedVersion},
    }};
    return {
        {QStringLiteral("id"), QStringLiteral("pkg:") + name},
        {QStringLiteral("name"), name},
        {QStringLiteral("summary"), p.desc},
        {QStringLiteral("icon"), QStringLiteral("image://icon/package-x-generic")},
        {QStringLiteral("developer"), QString()},
        {QStringLiteral("verified"), false},
        {QStringLiteral("description"), QString()},
        {QStringLiteral("screenshots"), QVariantList()},
        {QStringLiteral("homepage"), p.url},
        {QStringLiteral("license"), p.licenses},
        {QStringLiteral("categories"), QStringList()},
        {QStringLiteral("sources"), sources},
        {QStringLiteral("installed"), installedVersion.isEmpty() ? QString() : QStringLiteral("arch")},
        // Пакет без карточки — не программа из меню: «Открыть» нечего.
        {QStringLiteral("package"), true},
    };
}
