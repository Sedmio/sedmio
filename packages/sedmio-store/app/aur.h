#pragma once

#include <QNetworkAccessManager>
#include <QObject>
#include <QQmlEngine>
#include <QVariantList>
#include <QVariantMap>

// AUR — пакеты, которые пишут сами пользователи Arch; ставятся сборкой на
// своём компьютере (AurBuild). Здесь — поиск, сведения, PKGBUILD и
// обновления через AUR RPC.
//
// Урок Pamac: он спрашивал AUR на каждую нажатую клавишу и положил сервер
// (адреса пользователей банили). Здесь запрос — только когда человек сам
// попросил («Искать в AUR»), не чаще раза в 2 с, и ответы помним.
class Aur : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    // Последний поиск: [{name, base, version, summary, votes, popularity,
    // outOfDate, maintainer, updated, installed}].
    Q_PROPERTY(QVariantList results READ results NOTIFY resultsChanged)
    Q_PROPERTY(QString query READ query NOTIFY resultsChanged)
    Q_PROPERTY(bool searching READ searching NOTIFY resultsChanged)
    Q_PROPERTY(QString error READ error NOTIFY resultsChanged)
    // Установленные из AUR (пакеты, которых нет в репозиториях):
    // [{name, base, version, inAur, update, vcs}] — update: новая версия,
    // у пакетов -git — «новые коммиты», иначе "".
    Q_PROPERTY(QVariantList installed READ installed NOTIFY installedChanged)
    Q_PROPERTY(bool checking READ checking NOTIFY installedChanged)

public:
    static Aur *instance();
    static Aur *create(QQmlEngine *, QJSEngine *) { return instance(); }

    QVariantList results() const { return m_results; }
    QString query() const { return m_query; }
    bool searching() const { return m_searching; }
    QString error() const { return m_error; }
    QVariantList installed() const { return m_installed; }
    bool checking() const { return m_checking; }

    Q_INVOKABLE void search(const QString &text);
    Q_INVOKABLE void clear();
    // Сведения о пакете: done(map) — {name, base, version, summary, url,
    // license, votes, popularity, outOfDate, maintainer, updated, depends,
    // makeDepends}; пусто — не нашлось.
    Q_INVOKABLE void info(const QString &name, const QJSValue &done);
    Q_INVOKABLE void pkgbuild(const QString &base, const QJSValue &done);
    // Сверить установленные из AUR с AUR (одним запросом).
    Q_INVOKABLE void checkUpdates();
    // Установленная версия пакета ("" — не стоит) и сравнение версий
    // по правилам pacman.
    Q_INVOKABLE QString installedVersion(const QString &name) const;
    Q_INVOKABLE bool newer(const QString &version, const QString &than) const;

    // Для AurBuild: сведения о многих пакетах сразу (без QML).
    void infoMany(const QStringList &names, std::function<void(const QList<QVariantMap> &, const QString &error)> done);
    // Скачать с AUR (снимок пакета, .SRCINFO).
    void fetch(const QString &url, std::function<void(const QByteArray &, const QString &error)> done) { get(url, std::move(done)); }

    // Что помним об установленных отсюда пакетах
    // (~/.local/state/sedmio-store/aur.json): кто сопровождал и какие
    // коммиты были в ветках VCS — чтобы заметить смену сопровождающего и
    // новые коммиты у пакетов -git.
    QString rememberedMaintainer(const QString &name) const;
    void remember(const QString &name, const QString &maintainer, const QVariantMap &vcs);

Q_SIGNALS:
    void resultsChanged();
    void installedChanged();

private:
    explicit Aur(QObject *parent = nullptr);
    void get(const QString &path, std::function<void(const QByteArray &, const QString &error)> done);
    static QVariantMap fromJson(const QVariantMap &r);

    QNetworkAccessManager m_network;
    QVariantList m_results;
    QString m_query;
    bool m_searching = false;
    QString m_error;
    qint64 m_lastSearch = 0;
    QHash<QString, QVariantList> m_cache;
    QVariantList m_installed;
    bool m_checking = false;
    QVariantMap m_state;
    void loadState();
    void saveState() const;
    QString statePath() const;
    void checkVcs(QVariantList result);
};
