#include "defaults.h"

#include <KApplicationTrader>
#include <KConfigGroup>
#include <KService>
#include <KSharedConfig>
#include <KSycoca>

#include <QCollator>
#include <QProcess>
#include <QTimer>

namespace
{
struct Category {
    const char *id;
    const char *title;
    QStringList mimeTypes; // первый — по нему ищем программы
};

const QList<Category> &categoryList()
{
    static const QList<Category> list = {
        {"browser", "Браузер", {QStringLiteral("x-scheme-handler/https"), QStringLiteral("x-scheme-handler/http"), QStringLiteral("text/html"),
                                QStringLiteral("application/xhtml+xml")}},
        {"mail", "Почта", {QStringLiteral("x-scheme-handler/mailto")}},
        {"files", "Папки", {QStringLiteral("inode/directory")}},
        {"music", "Музыка", {QStringLiteral("audio/mpeg"), QStringLiteral("audio/flac"), QStringLiteral("audio/ogg"),
                              QStringLiteral("audio/x-vorbis+ogg"), QStringLiteral("audio/mp4"), QStringLiteral("audio/x-wav"),
                              QStringLiteral("audio/aac"), QStringLiteral("audio/x-opus+ogg")}},
        {"video", "Видео", {QStringLiteral("video/mp4"), QStringLiteral("video/x-matroska"), QStringLiteral("video/webm"),
                             QStringLiteral("video/x-msvideo"), QStringLiteral("video/quicktime"), QStringLiteral("video/mpeg")}},
        {"images", "Фото и картинки", {QStringLiteral("image/jpeg"), QStringLiteral("image/png"), QStringLiteral("image/gif"),
                                       QStringLiteral("image/webp"), QStringLiteral("image/bmp"), QStringLiteral("image/tiff"),
                                       QStringLiteral("image/avif")}},
        {"pdf", "PDF", {QStringLiteral("application/pdf")}},
        {"text", "Текст", {QStringLiteral("text/plain")}},
    };
    return list;
}

const Category *findCategory(const QString &id)
{
    for (const auto &category : categoryList()) {
        if (id == QLatin1String(category.id))
            return &category;
    }
    return nullptr;
}
} // namespace

Defaults::Defaults(QObject *parent)
    : QObject(parent)
{
    // Базу пересобрал кто-то другой (kded, модуль KDE, мы сами) — перечитать.
    connect(KSycoca::self(), &KSycoca::databaseChanged, this, &Defaults::load, Qt::QueuedConnection);
    load();
}

void Defaults::load()
{
    QCollator collator(QLocale(QLocale::Russian));
    QVariantList categories;
    for (const auto &category : categoryList()) {
        const QString mime = category.mimeTypes.constFirst();
        KService::List services = KApplicationTrader::queryByMimeType(mime);
        std::sort(services.begin(), services.end(), [&](const KService::Ptr &a, const KService::Ptr &b) {
            return collator.compare(a->name(), b->name()) < 0;
        });
        const KService::Ptr preferred = KApplicationTrader::preferredService(mime);

        QVariantList apps;
        int current = -1;
        for (const auto &service : std::as_const(services)) {
            if (service->noDisplay())
                continue;
            if (preferred && service->storageId() == preferred->storageId())
                current = int(apps.size());
            apps.append(QVariantMap{{QStringLiteral("id"), service->storageId()},
                                    {QStringLiteral("name"), service->name()},
                                    {QStringLiteral("icon"), service->icon()}});
        }
        categories.append(QVariantMap{{QStringLiteral("id"), QString::fromLatin1(category.id)},
                                      {QStringLiteral("title"), QString::fromUtf8(category.title)},
                                      {QStringLiteral("apps"), apps},
                                      {QStringLiteral("current"), current}});
    }
    m_categories = categories;
    Q_EMIT changed();
}

void Defaults::choose(const QString &categoryId, const QString &appId)
{
    const Category *category = findCategory(categoryId);
    const KService::Ptr service = KService::serviceByStorageId(appId);
    if (!category || !service)
        return;
    for (const QString &mime : category->mimeTypes)
        KApplicationTrader::setPreferredService(mime, service);

    if (categoryId == QLatin1String("browser")) {
        // Программы KDE берут браузер ещё и отсюда.
        KConfigGroup general(KSharedConfig::openConfig(QStringLiteral("kdeglobals")), QStringLiteral("General"));
        general.writeEntry("BrowserApplication", service->storageId(), KConfig::Notify | KConfig::Persistent);
        general.sync();
    }
    // Пока база пересобирается, показываем выбор сразу.
    for (QVariant &entry : m_categories) {
        QVariantMap map = entry.toMap();
        if (map.value(QStringLiteral("id")).toString() != categoryId)
            continue;
        const QVariantList apps = map.value(QStringLiteral("apps")).toList();
        for (int i = 0; i < apps.size(); ++i) {
            if (apps.at(i).toMap().value(QStringLiteral("id")).toString() == appId)
                map.insert(QStringLiteral("current"), i);
        }
        entry = map;
    }
    Q_EMIT changed();

    // Выбор попадает в базу KSycoca только при её пересборке, а проверка
    // устаревания внутри процесса ленивая и может пропустить свежий
    // mimeapps.list. Пересобираем явно, в стороне от окна, затем перечитываем.
    auto *rebuild = new QProcess(this);
    connect(rebuild, &QProcess::finished, this, [this, rebuild] {
        rebuild->deleteLater();
        KSycoca::self()->ensureCacheValid();
        load();
    });
    connect(rebuild, &QProcess::errorOccurred, this, [this, rebuild](QProcess::ProcessError error) {
        if (error != QProcess::FailedToStart)
            return;
        rebuild->deleteLater();
        // Нет kbuildsycoca6 — остаётся ленивая проверка; дадим ей время.
        QTimer::singleShot(2000, this, [this] {
            KSycoca::self()->ensureCacheValid();
            load();
        });
    });
    rebuild->start(QStringLiteral("kbuildsycoca6"), {});
}
