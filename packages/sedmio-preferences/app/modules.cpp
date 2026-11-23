#include "modules.h"

#include <QDir>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QStandardPaths>

namespace
{
const QString tool = QStringLiteral("sedmio-modules");
const QString modulesDir = QStringLiteral("/usr/share/sedmio/shell/modules");

QString configDir()
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation) + QStringLiteral("/sedmio");
}
} // namespace

Modules::Modules(QObject *parent)
    : QObject(parent)
{
    // Выбор меняют и отсюда, и sedmio-modules в терминале; модули ставят
    // пакеты. Файл выбора заменяется целиком — следим за папкой.
    m_reload.setSingleShot(true);
    m_reload.setInterval(200);
    connect(&m_reload, &QTimer::timeout, this, &Modules::load);
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, &m_reload, qOverload<>(&QTimer::start));
    watch();
    load();
}

void Modules::watch()
{
    QDir().mkpath(configDir());
    for (const QString &dir : {configDir(), modulesDir})
        if (!m_watcher.directories().contains(dir) && QDir(dir).exists())
            m_watcher.addPath(dir);
}

void Modules::load()
{
    watch();
    QProcess process;
    process.start(tool, {QStringLiteral("list"), QStringLiteral("--json")});
    if (!process.waitForFinished(5000) || process.exitStatus() != QProcess::NormalExit || process.exitCode() != 0) {
        setMessage(QStringLiteral("Не удалось получить список модулей (sedmio-modules)."));
        return;
    }
    const QJsonArray list = QJsonDocument::fromJson(process.readAllStandardOutput()).array();

    // Разделы в порядке первого модуля в них (sedmio-modules уже сортирует).
    QStringList names;
    QHash<QString, QVariantList> rows;
    for (const QJsonValue &value : list) {
        QVariantMap row = value.toObject().toVariantMap();
        QString group = row.value(QStringLiteral("group")).toString();
        if (group.isEmpty())
            group = QStringLiteral("Другое");
        if (!names.contains(group))
            names.append(group);
        rows[group].append(row);
    }

    for (const QString &name : names) {
        KeyedModel *&model = m_models[name];
        if (!model)
            model = new KeyedModel(QStringLiteral("id"), this);
        model->setItems(rows.value(name));
    }

    if (names != m_groupNames) {
        m_groupNames = names;
        m_groups.clear();
        for (const QString &name : names)
            m_groups.append(QVariantMap{{QStringLiteral("name"), name}, {QStringLiteral("model"), QVariant::fromValue(m_models.value(name))}});
        Q_EMIT groupsChanged();
    }
}

void Modules::setEnabled(const QString &id, bool enabled)
{
    run({enabled ? QStringLiteral("on") : QStringLiteral("off"), id});
}

void Modules::run(const QStringList &args)
{
    auto *process = new QProcess(this);
    connect(process, &QProcess::finished, this, [this, process](int code, QProcess::ExitStatus status) {
        if (status != QProcess::NormalExit || code != 0) {
            const QString error = QString::fromUtf8(process->readAllStandardError()).trimmed();
            setMessage(error.isEmpty() ? QStringLiteral("Не удалось переключить модуль.") : error);
        } else {
            setMessage(QString());
        }
        process->deleteLater();
        load();
    });
    connect(process, &QProcess::errorOccurred, this, [this, process](QProcess::ProcessError error) {
        if (error != QProcess::FailedToStart)
            return;
        setMessage(QStringLiteral("Не найдена программа sedmio-modules."));
        process->deleteLater();
    });
    process->start(tool, args);
}

void Modules::setMessage(const QString &message)
{
    if (message == m_message)
        return;
    m_message = message;
    Q_EMIT messageChanged();
}
