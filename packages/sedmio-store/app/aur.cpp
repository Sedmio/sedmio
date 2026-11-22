#include "aur.h"
#include "catalog.h"

#include <QDateTime>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QTimer>
#include <QUrl>
#include <QUrlQuery>

#include <alpm.h>

namespace
{
const QString rpc = QStringLiteral("https://aur.archlinux.org/rpc/v5");

QStringList strings(const QVariant &value)
{
    QStringList list;
    for (const QVariant &v : value.toList())
        list << v.toString();
    return list;
}
} // namespace

Aur::Aur(QObject *parent)
    : QObject(parent)
{
    m_network.setTransferTimeout(20000);
}

Aur *Aur::instance()
{
    static Aur *aur = new Aur;
    QJSEngine::setObjectOwnership(aur, QJSEngine::CppOwnership);
    return aur;
}

void Aur::get(const QString &path, std::function<void(const QByteArray &, const QString &)> done)
{
    QNetworkRequest request{QUrl(path.startsWith(QLatin1String("https:")) ? path : rpc + path)};
    request.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("sedmio-store"));
    QNetworkReply *reply = m_network.get(request);
    connect(reply, &QNetworkReply::finished, this, [reply, done] {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError) {
            const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
            done({}, status == 429 ? QStringLiteral("AUR просит подождать — слишком много запросов")
                     : status >= 500 ? QStringLiteral("AUR сейчас не отвечает — попробуйте позже")
                                     : QStringLiteral("Нет связи с AUR — проверьте интернет"));
            return;
        }
        done(reply->readAll(), {});
    });
}

QVariantMap Aur::fromJson(const QVariantMap &r)
{
    const qint64 modified = r.value(QStringLiteral("LastModified")).toLongLong();
    const QString name = r.value(QStringLiteral("Name")).toString();
    const Catalog *catalog = Catalog::instance();
    return {
        {QStringLiteral("name"), name},
        {QStringLiteral("base"), r.value(QStringLiteral("PackageBase")).toString()},
        {QStringLiteral("version"), r.value(QStringLiteral("Version")).toString()},
        {QStringLiteral("summary"), r.value(QStringLiteral("Description")).toString()},
        {QStringLiteral("url"), r.value(QStringLiteral("URL")).toString()},
        {QStringLiteral("license"), strings(r.value(QStringLiteral("License"))).join(QStringLiteral(", "))},
        {QStringLiteral("votes"), r.value(QStringLiteral("NumVotes")).toInt()},
        {QStringLiteral("popularity"), r.value(QStringLiteral("Popularity")).toDouble()},
        {QStringLiteral("outOfDate"), !r.value(QStringLiteral("OutOfDate")).isNull()},
        {QStringLiteral("maintainer"), r.value(QStringLiteral("Maintainer")).toString()},
        {QStringLiteral("updated"), modified > 0 ? QDateTime::fromSecsSinceEpoch(modified).date().toString(QStringLiteral("dd.MM.yyyy")) : QString()},
        {QStringLiteral("depends"), strings(r.value(QStringLiteral("Depends")))},
        {QStringLiteral("makeDepends"), strings(r.value(QStringLiteral("MakeDepends")))},
        {QStringLiteral("installed"), catalog ? catalog->packages().installed().value(name) : QString()},
    };
}

void Aur::search(const QString &text)
{
    const QString query = text.trimmed().toLower();
    if (query.size() < 2) {
        m_error = QStringLiteral("Наберите хотя бы две буквы");
        Q_EMIT resultsChanged();
        return;
    }
    m_query = query;
    if (m_cache.contains(query)) {
        m_results = m_cache.value(query);
        m_error.clear();
        m_searching = false;
        Q_EMIT resultsChanged();
        return;
    }
    // Не чаще раза в 2 с: AUR — общий сервер на всех пользователей Arch.
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    if (now - m_lastSearch < 2000) {
        m_searching = true;
        Q_EMIT resultsChanged();
        QTimer::singleShot(2000 - (now - m_lastSearch), this, [this, query] {
            if (m_query == query)
                search(query);
        });
        return;
    }
    m_lastSearch = now;
    m_searching = true;
    m_error.clear();
    Q_EMIT resultsChanged();
    get(QStringLiteral("/search/") + QString::fromUtf8(QUrl::toPercentEncoding(query)) + QStringLiteral("?by=name-desc"),
        [this, query](const QByteArray &data, const QString &error) {
            if (m_query != query)
                return;
            m_searching = false;
            if (!error.isEmpty()) {
                m_error = error;
                m_results.clear();
                Q_EMIT resultsChanged();
                return;
            }
            const QVariantMap json = QJsonDocument::fromJson(data).object().toVariantMap();
            if (json.value(QStringLiteral("type")) == QLatin1String("error")) {
                const QString message = json.value(QStringLiteral("error")).toString();
                m_error = message.contains(QLatin1String("Too many")) ? QStringLiteral("Слишком много совпадений — уточните запрос")
                                                                       : QStringLiteral("AUR: ") + message;
                m_results.clear();
                Q_EMIT resultsChanged();
                return;
            }
            QList<QVariantMap> list;
            for (const QVariant &v : json.value(QStringLiteral("results")).toList())
                list << fromJson(v.toMap());
            // Точное имя — первым, дальше — по популярности.
            std::sort(list.begin(), list.end(), [&query](const QVariantMap &a, const QVariantMap &b) {
                const bool ea = a.value(QStringLiteral("name")) == query;
                const bool eb = b.value(QStringLiteral("name")) == query;
                if (ea != eb)
                    return ea;
                return a.value(QStringLiteral("popularity")).toDouble() > b.value(QStringLiteral("popularity")).toDouble();
            });
            QVariantList results;
            for (qsizetype i = 0; i < list.size() && i < 60; ++i)
                results << list.at(i);
            m_results = results;
            m_error = results.isEmpty() ? QStringLiteral("В AUR ничего не нашлось") : QString();
            m_cache.insert(query, results);
            Q_EMIT resultsChanged();
        });
}

void Aur::clear()
{
    m_query.clear();
    m_results.clear();
    m_error.clear();
    m_searching = false;
    Q_EMIT resultsChanged();
}

void Aur::infoMany(const QStringList &names, std::function<void(const QList<QVariantMap> &, const QString &)> done)
{
    if (names.isEmpty()) {
        done({}, {});
        return;
    }
    QUrlQuery query;
    for (const QString &name : names)
        query.addQueryItem(QStringLiteral("arg[]"), name);
    get(QStringLiteral("/info?") + query.toString(QUrl::FullyEncoded), [done](const QByteArray &data, const QString &error) {
        if (!error.isEmpty()) {
            done({}, error);
            return;
        }
        QList<QVariantMap> list;
        const QVariantMap json = QJsonDocument::fromJson(data).object().toVariantMap();
        for (const QVariant &v : json.value(QStringLiteral("results")).toList())
            list << fromJson(v.toMap());
        done(list, {});
    });
}

void Aur::info(const QString &name, const QJSValue &done)
{
    QJSValue callback = done;
    infoMany({name}, [callback](const QList<QVariantMap> &list, const QString &error) mutable {
        if (!callback.isCallable())
            return;
        QVariantMap result = list.isEmpty() ? QVariantMap() : list.constFirst();
        if (!error.isEmpty())
            result.insert(QStringLiteral("error"), error);
        QJSEngine *engine = qjsEngine(Aur::instance());
        callback.call({engine ? engine->toScriptValue(result) : QJSValue()});
    });
}

void Aur::pkgbuild(const QString &base, const QJSValue &done)
{
    QJSValue callback = done;
    get(QStringLiteral("https://aur.archlinux.org/cgit/aur.git/plain/PKGBUILD?h=") + QString::fromUtf8(QUrl::toPercentEncoding(base)),
        [callback](const QByteArray &data, const QString &error) mutable {
            if (callback.isCallable())
                callback.call({QJSValue(error.isEmpty() ? QString::fromUtf8(data) : QString()), QJSValue(error)});
        });
}

void Aur::checkUpdates()
{
    const Catalog *catalog = Catalog::instance();
    if (!catalog || m_checking)
        return;
    const Packages &packages = catalog->packages();
    if (!packages.hasSync())
        return;
    // Не из репозиториев — значит, из AUR (или поставлено вручную).
    QStringList foreign;
    for (auto it = packages.installed().cbegin(); it != packages.installed().cend(); ++it) {
        if (!packages.sync().contains(it.key()))
            foreign << it.key();
    }
    foreign.sort();
    m_checking = true;
    Q_EMIT installedChanged();
    infoMany(foreign, [this, foreign](const QList<QVariantMap> &list, const QString &) {
        const Catalog *catalog = Catalog::instance();
        QHash<QString, QString> latest;
        for (const QVariantMap &m : list)
            latest.insert(m.value(QStringLiteral("name")).toString(), m.value(QStringLiteral("version")).toString());
        QVariantList result;
        for (const QString &name : foreign) {
            const QString version = catalog ? catalog->packages().installed().value(name) : QString();
            const QString newer = latest.value(name);
            const bool update = !newer.isEmpty()
                && alpm_pkg_vercmp(newer.toUtf8().constData(), version.toUtf8().constData()) > 0;
            result << QVariantMap{{QStringLiteral("name"), name},
                                  {QStringLiteral("version"), version},
                                  {QStringLiteral("inAur"), latest.contains(name)},
                                  {QStringLiteral("update"), update ? newer : QString()}};
        }
        m_installed = result;
        m_checking = false;
        Q_EMIT installedChanged();
    });
}

QString Aur::installedVersion(const QString &name) const
{
    const Catalog *catalog = Catalog::instance();
    return catalog ? catalog->packages().installed().value(name) : QString();
}

bool Aur::newer(const QString &version, const QString &than) const
{
    return !version.isEmpty() && !than.isEmpty() && alpm_pkg_vercmp(version.toUtf8().constData(), than.toUtf8().constData()) > 0;
}
