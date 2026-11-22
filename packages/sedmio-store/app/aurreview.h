#pragma once

#include <QHash>
#include <QObject>
#include <QPointer>
#include <QProcess>
#include <QQmlEngine>
#include <QSet>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>

#include <functional>

#include "pkgscan.h"

// Просмотр пакетов AUR перед сборкой (страница AurReviewPage).
//
//  1. Что нужно: сами пакеты и их зависимости из AUR (каждую тоже
//     смотрим), из репозиториев — списком с размером.
//  2. Каждый пакет скачивается один раз — сюда, в
//     ~/.cache/sedmio-store/aur/review/<base>; показываем все его файлы
//     и находки автопроверки (PkgScan).
//  3. План (plan()) запоминает отпечаток (sha256) скачанного. Собирается
//     копия ровно этих файлов: правка в AUR после просмотра в сборку не
//     попадёт, а изменённые на диске файлы AurBuild не возьмёт.
class AurReview : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    // "" — ещё не начали, loading, ready, failed.
    Q_PROPERTY(QString state READ state NOTIFY changed)
    Q_PROPERTY(QString status READ status NOTIFY changed)
    Q_PROPERTY(QString error READ error NOTIFY changed)
    // [{base, names, version, installed, summary, maintainer, votes,
    //   submitted, updated, url, target, files: [{name, binary, size}],
    //   findings: [{level, file, line, message}], danger, check, note,
    //   reviewed}] — в порядке сборки, нужные раньше.
    Q_PROPERTY(QVariantList packages READ packages NOTIFY changed)
    Q_PROPERTY(QStringList repoDeps READ repoDeps NOTIFY changed)
    Q_PROPERTY(qint64 repoDownload READ repoDownload NOTIFY changed)
    Q_PROPERTY(bool allReviewed READ allReviewed NOTIFY changed)

public:
    explicit AurReview(QObject *parent = nullptr);

    QString state() const { return m_state; }
    QString status() const { return m_status; }
    QString error() const { return m_error; }
    QVariantList packages() const;
    QStringList repoDeps() const { return m_repoDeps; }
    qint64 repoDownload() const { return m_repoDownload; }
    bool allReviewed() const;

    // targets — что поставить или обновить (имена пакетов AUR).
    Q_INVOKABLE void start(const QStringList &targets);
    Q_INVOKABLE QString fileText(const QString &base, const QString &file) const;
    Q_INVOKABLE void setReviewed(const QString &base, bool reviewed);
    // Для Jobs.buildAur: {targets, order: [{name, base}], repoDeps,
    // bases: {base: {dir, hash, maintainer, vcs: {"url ref": commit}}}}.
    Q_INVOKABLE QVariantMap plan() const;

    // Отпечаток папки: пути и содержимое всех файлов.
    static QByteArray treeHash(const QString &dir);
    static QString reviewDir(const QString &base);

Q_SIGNALS:
    void changed();

private:
    struct Base {
        QString base;
        QStringList names;   // какие пакеты из него нужны
        QVariantMap info;    // Aur::fromJson первого из них
        QList<PkgScan::File> files;
        QStringList binary;  // файлы, которые не текст
        QHash<QString, qint64> sizes;
        QList<PkgScan::Finding> findings;
        QByteArray hash;
        QHash<QString, QString> vcs;
        bool reviewed = false;
        bool target = false;
    };

    void resolve(const QStringList &names);
    void classify(const QStringList &missing);
    void resolved();
    void fetchNext();
    void inspect(Base &base);
    void finishPlan();
    void fail(const QString &error);
    void setStatus(const QString &status);
    void run(const QString &program, const QStringList &args, std::function<void(int, const QString &)> done,
             const QString &workdir = {}, bool cLocale = false);

    QString m_state;
    QString m_status;
    QString m_error;
    QStringList m_targets;
    QHash<QString, QVariantMap> m_aur;      // имя → сведения AUR
    QHash<QString, QStringList> m_depends;  // имя → зависимости (без версий)
    QStringList m_pending;
    QSet<QString> m_seen;
    QStringList m_repoDeps;
    qint64 m_repoDownload = 0;
    QStringList m_order;                    // имена, нужные раньше
    QList<Base> m_bases;                    // в порядке сборки
    int m_fetchIndex = 0;
    int m_generation = 0;                   // новый start() — старые ответы не нужны
};
