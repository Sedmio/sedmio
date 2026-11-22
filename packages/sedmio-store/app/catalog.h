#pragma once

#include <QHash>
#include <QSet>
#include <QObject>
#include <QQmlEngine>
#include <QVariantList>
#include <QVariantMap>

#include <memory>

#include "packages.h"

namespace AppStream
{
class Pool;
}

// Каталог «Программ»: программы из двух источников — репозиториев Arch
// (AppStream из archlinux-appstream-data) и Flathub (AppStream, который
// flatpak скачивает сам), сведённые в одну карточку, если это одна
// программа. Источник выбирает человек в карточке, каждый раз.
//
// Что установлено и что реально есть в репозиториях — из Packages
// (pacman, flatpak), а не из каталога.
//
// Каталог грузится в своём потоке (первый раз Flathub — около секунды),
// дальше в памяти — только то, что нужно для поиска и плиток; подробности
// карточки берутся из AppStream по запросу.
class Catalog : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(bool ready READ ready NOTIFY readyChanged)
    // Flathub подключён и его каталог есть.
    Q_PROPERTY(bool flathub READ flathub NOTIFY readyChanged)
    // [{key, title, icon}]
    Q_PROPERTY(QVariantList categories READ categories CONSTANT)
    // Растёт, когда меняется установленное: списки в QML перечитываются.
    Q_PROPERTY(int revision READ revision NOTIFY revisionChanged)
    // Каталог Flathub: "" — в порядке, "loading" — скачивается, иначе ошибка.
    Q_PROPERTY(QString flathubStatus READ flathubStatus NOTIFY flathubStatusChanged)
    // Обновления программ Flathub: плитки + ref; проверяются по checkUpdates().
    Q_PROPERTY(QVariantList updates READ updates NOTIFY updatesChanged)
    Q_PROPERTY(bool checkingUpdates READ checkingUpdates NOTIFY updatesChanged)
    Q_PROPERTY(QString updatesError READ updatesError NOTIFY updatesChanged)

public:
    explicit Catalog(QObject *parent = nullptr);
    ~Catalog() override;
    // Созданный движком QML (для Aur и AurBuild); nullptr — ещё нет.
    static Catalog *instance();
    const Packages &packages() const { return m_packages; }

    bool ready() const { return m_ready; }
    bool flathub() const { return m_flathub; }
    QVariantList categories() const;
    int revision() const { return m_revision; }
    QString flathubStatus() const { return m_flathubStatus; }
    QVariantList updates() const { return m_updates; }
    bool checkingUpdates() const { return m_checkingUpdates; }
    QString updatesError() const { return m_updatesError; }

    // Плитки: [{id, name, summary, icon, arch, flathub, installed, verified}].
    Q_INVOKABLE QVariantList search(const QString &text, int limit = 80) const;
    Q_INVOKABLE QVariantList featured() const;
    Q_INVOKABLE QVariantList category(const QString &key, int limit = 400) const;
    Q_INVOKABLE QVariantList installedApps() const;
    // Пакеты репозиториев, у которых нет карточки в каталоге (консольные
    // программы, шрифты, библиотеки): [{id: "pkg:<имя>", name, summary,
    // version, repo, installed}]. Карточка — details("pkg:<имя>").
    Q_INVOKABLE QVariantList searchPackages(const QString &text, int limit = 40) const;
    // Карточка программы; пусто — нет такой.
    Q_INVOKABLE QVariantMap details(const QString &id) const;
    // Чья программа из меню (id её .desktop): {key} — есть в каталоге;
    // {package, foreign, name, icon} — пакет вне каталога (foreign — не
    // из репозиториев: AUR или поставлен вручную); {} — не нашлось.
    Q_INVOKABLE QVariantMap resolveDesktop(const QString &desktopId) const;
    // Открыть установленную программу; kind — "arch" | "flathub".
    Q_INVOKABLE bool launch(const QString &id, const QString &kind) const;
    Q_INVOKABLE void checkUpdates();

    struct Entry {
        QString key;           // id строчными, без .desktop
        QString archId;        // id компонента в каталоге Arch
        QString flatpakId;     // … и Flathub
        QString package;       // пакет Arch
        QString flatpakRef;    // app/<id>/x86_64/stable
        QString flatpakOrigin; // удалённый репозиторий (flathub)
        QString archDesktop;   // .desktop программы — чтобы её открыть
        QString flatpakDesktop;
        QString name;
        QString summary;
        QString icon;          // file:// или https://, или image://icon/<имя>
        QString developer;
        QStringList categories;
        bool verified = false; // Flathub проверил разработчика
        bool russian = false;  // описание переведено
        int screenshots = 0;
        int curated = -1;      // место в подборке
        // Для поиска — нормализованные (TextMatch::normalize).
        QString nName;
        QString nNameC;
        QString nSummary;
        QString nDeveloper;
        QStringList nNameWords;
        QStringList nKeywords;
        QStringList nIds;      // пакет, хвост id (kdenlive), id flatpak
    };

Q_SIGNALS:
    void readyChanged();
    void revisionChanged();
    void flathubStatusChanged();
    void updatesChanged();

private:
    struct Loaded;
    void load();
    void finishLoad(Loaded *loaded);
    void refreshFlathub();
    void setFlathubStatus(const QString &status);

    // Источники, которые действительно можно поставить или удалить.
    bool archAvailable(const Entry &entry) const;
    bool flathubAvailable(const Entry &entry) const;
    QString installedSource(const Entry &entry) const;
    bool visible(const Entry &entry) const;
    QVariantMap tile(const Entry &entry) const;
    int quality(const Entry &entry) const;
    // Слово запроса и что ещё под ним понимать (synonymList в catalog.cpp).
    struct Word {
        QString text;
        QStringList english;
        QStringList categories;
    };
    static Word makeWord(const QString &text);
    int score(const Entry &entry, const QList<Word> &words, const QString &whole) const;

    std::unique_ptr<AppStream::Pool> m_archPool;
    std::unique_ptr<AppStream::Pool> m_flatpakPool;
    QList<Entry> m_entries;
    // Все пакеты баз синхронизации: описание и прочее для «Пакетов».
    struct PkgInfo {
        QString name;
        QString desc;
        QString url;
        QString licenses;
        qint64 installedSize = 0;
        QString nName;
        QString nDesc;
    };
    QHash<QString, PkgInfo> m_pkgInfo;
    QSet<QString> m_catalogPackages; // пакеты, у которых есть карточка
    int m_pkgIndexFor = -1;          // по скольким пакетам sync строили
    bool m_pkgIndexLoading = false;
    void loadPackageIndex();
    QVariantMap packageDetails(const QString &name) const;
    QHash<QString, qsizetype> m_byKey;
    Packages m_packages;
    bool m_ready = false;
    bool m_flathub = false;
    int m_revision = 0;
    QString m_flathubStatus;
    bool m_refreshed = false;
    QVariantList m_updates;
    bool m_checkingUpdates = false;
    QString m_updatesError;
};
