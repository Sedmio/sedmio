#pragma once

#include <QHash>
#include <QJSValue>
#include <QNetworkAccessManager>
#include <QObject>
#include <QPointer>
#include <QQmlEngine>
#include <QVariantList>
#include <QVariantMap>

class QNetworkReply;

// AppImage — программа одним файлом. Сами по себе они живут где попало
// («Загрузки»), в меню не попадают и не обновляются. Здесь: файл — в
// ~/Applications, значок и пункт меню — из него самого (без запуска:
// читаем образ squashfs, unsquashfs), обновления — с GitHub, если файл
// сам говорит, откуда он (.upd_info), или человек указал проект.
//
// Песочницы у AppImage нет: программа может всё, что может человек, —
// об этом говорим перед добавлением.
class AppImages : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    // [{id, name, comment, icon (file://), version, file, size, github,
    //   update, desktop}] — update: новый выпуск на GitHub или "".
    Q_PROPERTY(QVariantList list READ list NOTIFY listChanged)
    // Что сейчас делается: {id: {text, progress (0…1, -1 — неизвестно),
    // error, done}}; id "@add" — добавление нового.
    Q_PROPERTY(QVariantMap work READ work NOTIFY workChanged)
    Q_PROPERTY(bool checking READ checking NOTIFY listChanged)

public:
    static AppImages *instance();
    static AppImages *create(QQmlEngine *, QJSEngine *) { return instance(); }

    QVariantList list() const { return m_list; }
    QVariantMap work() const { return m_work; }
    bool checking() const { return m_checking > 0; }

    // Что внутри файла (не запуская его): done({ok, error, path, name,
    // comment, version, size, icon (data:), github, existing, existingVersion}).
    Q_INVOKABLE void inspect(const QString &path, const QJSValue &done);
    // Последний выпуск на GitHub: «владелец/проект» или ссылка.
    // done({ok, error, repo, tag, title, published, asset, size, url, digest}).
    Q_INVOKABLE void findRelease(const QString &repo, const QJSValue &done);
    // Добавить файл (перенести в ~/Applications) или скачать выпуск.
    // github — «владелец/проект» для обновлений, можно "".
    Q_INVOKABLE void add(const QString &path, const QString &github);
    Q_INVOKABLE void addRelease(const QVariantMap &release);
    Q_INVOKABLE void update(const QString &id);
    Q_INVOKABLE void remove(const QString &id);
    Q_INVOKABLE bool launch(const QString &id) const;
    Q_INVOKABLE void setGitHub(const QString &id, const QString &repo);
    // Сверить с GitHub; без force — не чаще раза в 6 часов.
    Q_INVOKABLE void checkUpdates(bool force = false);
    Q_INVOKABLE void cancel(const QString &id);
    Q_INVOKABLE void dismiss(const QString &id);
    // Чей это пункт меню (appimage-<id>.desktop) — id или "".
    Q_INVOKABLE QString byDesktop(const QString &desktopId) const;
    Q_INVOKABLE QVariantMap get(const QString &id) const;
    // «владелец/проект» из ссылки или как есть; "" — не похоже.
    Q_INVOKABLE static QString parseRepo(const QString &text);

    // Разбор файла и установка — в своём потоке (см. .cpp).
    struct Inspected {
        QString error;
        qint64 offset = 0;
        qint64 size = 0;
        QString desktopName; // orca-ide.desktop
        QByteArray desktop;
        QByteArray icon;
        QString iconExt; // png | svg | svgz | xpm
        QString updateInfo;
        QString name, comment, version;
    };
    static Inspected inspectFile(const QString &path);

Q_SIGNALS:
    void listChanged();
    void workChanged();
    // Добавление закончилось: id новой программы.
    void added(const QString &id);

private:
    explicit AppImages(QObject *parent = nullptr);
    QString statePath() const;
    void load();
    void save() const;
    void rebuild();
    void setWork(const QString &id, const QString &text, double progress, const QString &error = {}, bool done = false);
    QString makeId(const Inspected &in, const QString &path) const;
    void install(const QString &workId, const QString &path, bool ownsFile, const QVariantMap &meta);
    void download(const QString &workId, const QVariantMap &release, std::function<void(const QString &path)> done);
    void apiGet(const QString &path, std::function<void(const QVariantMap &, const QString &error)> done);
    static QVariantMap pickAsset(const QVariantMap &release, const QString &pattern);
    void checkOne(const QString &id);

    QNetworkAccessManager m_network;
    QVariantMap m_state; // id → {name, comment, version, file, desktop, icon, github, pattern, tag, latest, size}
    QVariantList m_list;
    QVariantMap m_work;
    QHash<QString, QPointer<QNetworkReply>> m_downloads;
    int m_checking = 0;
};
