#pragma once

#include <QDBusAbstractAdaptor>
#include <QElapsedTimer>
#include <QHash>
#include <QObject>
#include <QPointer>
#include <QQmlEngine>
#include <QQuickWindow>
#include <QTimer>
#include <QVariantList>

#include "keyedmodel.h"

// «Диспетчер задач» (Ctrl+Shift+Esc): что работает и сколько берёт, и
// кнопка «Завершить» для зависшего.
//
// Источник — группы systemd пользователя (cgroup v2), а не список
// процессов: каждая программа запущена в своей группе app-<id>-….scope
// (оболочка — /usr/lib/sedmio/launch, программы KDE — сами), и в группе
// уже посчитаны память (memory.current) и процессор (cpu.stat) всех её
// процессов вместе с дочерними. Завершить — остановить группу через
// systemd: SIGTERM всем процессам; не помогло за 5 с — можно добить
// (SIGKILL). Части системы (оболочка, KWin, звук…) показаны отдельно,
// завершать их нельзя; оболочку можно перезапустить — программы в своих
// группах это переживают.
class Tasks : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    // [{key, name, icon, cpu, memory, memoryText, processes, ending, hung}]
    Q_PROPERTY(QVariantList apps READ apps NOTIFY changed)
    // [{key, name, icon, cpu, memory, memoryText, restartable}]
    Q_PROPERTY(QVariantList system READ system NOTIFY changed)
    // Те же списки моделью (строки не пересоздаются раз в 2 с).
    Q_PROPERTY(KeyedModel *appModel READ appModel CONSTANT)
    Q_PROPERTY(KeyedModel *systemModel READ systemModel CONSTANT)
    // Порядок программ: "name" | "cpu" | "memory".
    Q_PROPERTY(QString sortBy READ sortBy WRITE setSortBy NOTIFY sortByChanged)
    // Процессор всего, %.
    Q_PROPERTY(double cpu READ cpu NOTIFY changed)
    Q_PROPERTY(qint64 memoryUsed READ memoryUsed NOTIFY changed)
    Q_PROPERTY(qint64 memoryTotal READ memoryTotal NOTIFY changed)
    Q_PROPERTY(QString memoryText READ memoryText NOTIFY changed)
    // Обновлять раз в 2 с (пока окно видно).
    Q_PROPERTY(bool running READ running WRITE setRunning NOTIFY runningChanged)
    Q_PROPERTY(QString message READ message NOTIFY changed)
    // Группы systemd недоступны — показывать нечего.
    Q_PROPERTY(bool available READ available NOTIFY changed)

public:
    explicit Tasks(QObject *parent = nullptr);

    QVariantList apps() const { return m_apps; }
    QVariantList system() const { return m_system; }
    KeyedModel *appModel() const { return m_appModel; }
    KeyedModel *systemModel() const { return m_systemModel; }
    QString sortBy() const { return m_sortBy; }
    void setSortBy(const QString &sortBy);
    double cpu() const { return m_cpu; }
    qint64 memoryUsed() const { return m_memoryUsed; }
    qint64 memoryTotal() const { return m_memoryTotal; }
    QString memoryText() const;
    bool running() const { return m_timer.isActive(); }
    void setRunning(bool running);
    QString message() const { return m_message; }
    bool available() const { return !m_root.isEmpty(); }

    Q_INVOKABLE void end(const QString &key);
    Q_INVOKABLE void forceEnd(const QString &key);
    Q_INVOKABLE void restartShell();
    Q_INVOKABLE void refresh();

    static QString formatBytes(qint64 bytes);

Q_SIGNALS:
    void changed();
    void runningChanged();
    void sortByChanged();

private:
    struct Unit {
        QString name;  // имя группы = имя юнита systemd (с \x2d)
        QString path;  // каталог в /sys/fs/cgroup
    };
    struct Group {
        QString key;
        QString name;
        QString icon;
        QList<Unit> units;
        qint64 memory = 0;
        double cpu = 0;
        int processes = 0;
        int order = 0;
    };

    void scanDirectory(const QString &dir, const QString &slice);
    void addUnit(const QString &unit, const QString &path, const QString &slice);
    void identify(Group &group, const QString &unit, const QString &path) const;
    double unitCpu(const QString &path, quint64 elapsedUs);
    void readTotals(quint64 elapsedUs);
    void callSystemd(const QString &method, const QVariantList &args);

    QString m_root;  // …/user@UID.service
    QTimer m_timer;
    QElapsedTimer m_clock;
    quint64 m_lastScan = 0;
    QHash<QString, quint64> m_cpuUsage;  // путь группы → usage_usec прошлого замера
    quint64 m_lastCpuBusy = 0;
    quint64 m_lastCpuTotal = 0;

    QHash<QString, Group> m_appGroups;
    QHash<QString, Group> m_systemGroups;
    QHash<QString, qint64> m_ending;  // key → когда попросили завершить (мс)
    QHash<QString, QPair<QString, QString>> m_names;  // id → (имя, значок), кэш

    QVariantList m_apps;
    QVariantList m_system;
    KeyedModel *m_appModel;
    KeyedModel *m_systemModel;
    QString m_sortBy = QStringLiteral("name");
    double m_cpu = 0;
    qint64 m_memoryUsed = 0;
    qint64 m_memoryTotal = 0;
    QString m_message;
};

// Одно окно диспетчера на сеанс (org.sedmio.Tasks): повторный
// Ctrl+Shift+Esc поднимает открытое.
class TasksHost : public QObject
{
    Q_OBJECT

public:
    explicit TasksHost(QObject *parent = nullptr);
    void setWindow(QQuickWindow *window) { m_window = window; }
    bool registerOnBus();
    static bool forward();

public Q_SLOTS:
    void show(const QString &token);

private:
    QPointer<QQuickWindow> m_window;
};

class TasksAdaptor : public QDBusAbstractAdaptor
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.sedmio.Tasks")

public:
    explicit TasksAdaptor(TasksHost *host)
        : QDBusAbstractAdaptor(host)
        , m_host(host)
    {
    }

public Q_SLOTS:
    void Show(const QString &token) { m_host->show(token); }

private:
    TasksHost *m_host;
};
