#pragma once

#include <QObject>
#include <QPointer>
#include <QProcess>
#include <QQmlEngine>
#include <QVariantList>
#include <QVariantMap>

typedef struct _GCancellable GCancellable;

// Очередь установок, удалений и обновлений. По одному за раз: pacman и
// так не даст двоих, а очередь видна человеку («ждёт»).
//
// Arch — через /usr/lib/sedmio/store-helper (pkexec, пароль); Flathub —
// libflatpak в своём потоке (без пароля, к пользователю); AUR — AurBuild
// (сборка от пользователя, установка — тем же помощником).
//
// Окно закрыли, а работа идёт — программа живёт до конца очереди и
// сообщает итог уведомлением (main.cpp).
class Jobs : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    // [{id, appId, name, icon, kind, action, state, progress, text, error, code}]
    // state: waiting | running | done | failed | cancelled.
    // code (при failed): 3 — занято, 4 — базы пакетов устарели.
    Q_PROPERTY(QVariantList list READ list NOTIFY changed)
    Q_PROPERTY(bool busy READ busy NOTIFY changed)
    // Растёт, когда в каком-нибудь журнале прибавилось (Jobs.log(id)).
    Q_PROPERTY(int logRevision READ logRevision NOTIFY logChanged)

public:
    static Jobs *instance();
    static Jobs *create(QQmlEngine *, QJSEngine *) { return instance(); }

    QVariantList list() const;
    bool busy() const;
    int logRevision() const { return m_logRevision; }

    // app — Catalog.details(); kind — "arch" | "flathub".
    Q_INVOKABLE void install(const QVariantMap &app, const QString &kind);
    Q_INVOKABLE void remove(const QVariantMap &app, const QString &kind, bool deleteData);
    // AUR: plan — AurReview.plan() (только просмотренное); action —
    // "install" или "update".
    Q_INVOKABLE void buildAur(const QVariantMap &plan, const QString &action);
    Q_INVOKABLE void removeAur(const QString &name);
    // Обновить программы Flathub: [{id, ref, name, icon}]; пусто — все.
    Q_INVOKABLE void updateFlatpaks(const QVariantList &apps);
    // Последнее задание программы (идёт, ждёт или только что кончилось).
    Q_INVOKABLE QVariantMap forApp(const QString &appId) const;
    Q_INVOKABLE void cancel(int id);
    Q_INVOKABLE void dismiss(int id);
    // Что выводили pacman и makepkg (последние ~300 КБ).
    Q_INVOKABLE QString log(int id) const;

Q_SIGNALS:
    void changed();
    void logChanged();
    void finished(const QString &appId, const QString &name, const QString &action, bool ok, const QString &error);

private:
    struct Job {
        int id = 0;
        QString appId;
        QString name;
        QString icon;
        QString kind;
        QString action;      // install | remove | update
        QStringList targets; // пакеты или ref
        QString origin;
        bool user = true;
        bool deleteData = false;
        QString state = QStringLiteral("waiting");
        double progress = -1;
        QString text;
        QString error;
        int code = 0;
        GCancellable *cancellable = nullptr;
        QPointer<QProcess> process;
        QPointer<QObject> build;
        QVariantMap plan;
        QString log;
    };

    explicit Jobs(QObject *parent = nullptr);
    void enqueue(Job job);
    void next();
    void runPacman(Job &job);
    void runFlatpak(Job &job);
    void runAur(Job &job);
    void finish(int id, const QString &error, int code = 0);
    Job *find(int id);
    QVariantMap toMap(const Job &job) const;
    void appendLog(int id, const QString &text);

    QList<Job> m_jobs;
    int m_nextId = 1;
    int m_logRevision = 0;
    bool m_logPending = false;
};
