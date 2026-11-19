#include "updates.h"

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusReply>
#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocale>
#include <QProcess>
#include <QRegularExpression>
#include <QStandardPaths>

namespace
{
const QString helper = QStringLiteral("/usr/lib/sedmio/update-helper");
const QString lister = QStringLiteral("/usr/lib/sedmio/update-snapshots");
const QString checker = QStringLiteral("/usr/lib/sedmio/update-check");
const QString upgradeState = QStringLiteral("/run/sedmio-update/upgrade.json");
const QString upgradeLog = QStringLiteral("/run/sedmio-update/upgrade.log");

QString checkStateFile()
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericStateLocation) + QStringLiteral("/sedmio/updates.json");
}

QJsonObject readObject(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
        return {};
    return QJsonDocument::fromJson(file.readAll()).object();
}

QString plural(qint64 n, const QString &one, const QString &few, const QString &many)
{
    const qint64 d = n % 10, h = n % 100;
    if (d == 1 && h != 11)
        return one;
    if (d >= 2 && d <= 4 && (h < 12 || h > 14))
        return few;
    return many;
}

QString packageList(const QStringList &names, int count)
{
    QString text = names.mid(0, 3).join(QStringLiteral(", "));
    if (count > 3)
        text += QStringLiteral(" и ещё %1").arg(count - 3);
    return text;
}

// Служба обновления ещё есть (systemd-run --collect: кончилась — пропала).
bool upgradeUnitAlive()
{
    QDBusMessage call = QDBusMessage::createMethodCall(QStringLiteral("org.freedesktop.systemd1"), QStringLiteral("/org/freedesktop/systemd1"),
                                                       QStringLiteral("org.freedesktop.systemd1.Manager"), QStringLiteral("GetUnit"));
    call << QStringLiteral("sedmio-upgrade.service");
    const QDBusMessage reply = QDBusConnection::systemBus().call(call, QDBus::Block, 2000);
    return reply.type() == QDBusMessage::ReplyMessage;
}
} // namespace

Updates::Updates(QObject *parent)
    : QObject(parent)
{
    // Пока идёт обновление — раз в секунду, иначе реже: обновление могли
    // начать и не отсюда (другое окно, уведомление).
    m_poll.setInterval(3000);
    connect(&m_poll, &QTimer::timeout, this, &Updates::readUpgradeState);
    m_poll.start();
    readCheckState();
    readUpgradeState();
    refresh();
}

QString Updates::humanDate(const QDateTime &when)
{
    if (!when.isValid())
        return {};
    const QLocale ru(QLocale::Russian);
    const QDate today = QDate::currentDate();
    const QString time = when.toString(QStringLiteral("HH:mm"));
    if (when.date() == today)
        return QStringLiteral("сегодня, ") + time;
    if (when.date() == today.addDays(-1))
        return QStringLiteral("вчера, ") + time;
    if (when.date().year() == today.year())
        return ru.toString(when.date(), QStringLiteral("d MMMM")) + QStringLiteral(", ") + time;
    return ru.toString(when.date(), QStringLiteral("d MMMM yyyy")) + QStringLiteral(", ") + time;
}

QString Updates::lastCheck() const
{
    return m_checked > 0 ? humanDate(QDateTime::fromSecsSinceEpoch(m_checked)) : QString();
}

// ---- Проверка

void Updates::readCheckState()
{
    const QJsonObject state = readObject(checkStateFile());
    m_checked = state.value(QStringLiteral("checked")).toInteger();
    m_checkError = state.value(QStringLiteral("error")).toString();
    m_updates.clear();
    const QJsonArray list = state.value(QStringLiteral("updates")).toArray();
    for (const QJsonValue &v : list) {
        const QJsonObject o = v.toObject();
        m_updates.append(QVariantMap{{QStringLiteral("name"), o.value(QStringLiteral("name")).toString()},
                                     {QStringLiteral("old"), o.value(QStringLiteral("old")).toString()},
                                     {QStringLiteral("new"), o.value(QStringLiteral("new")).toString()}});
    }
    Q_EMIT updatesChanged();
}

void Updates::check()
{
    if (m_checking)
        return;
    m_checking = true;
    Q_EMIT updatesChanged();
    auto *process = new QProcess(this);
    connect(process, &QProcess::finished, this, [this, process] {
        process->deleteLater();
        m_checking = false;
        readCheckState();
    });
    connect(process, &QProcess::errorOccurred, this, [this, process](QProcess::ProcessError error) {
        if (error != QProcess::FailedToStart)
            return;
        process->deleteLater();
        m_checking = false;
        m_checkError = QStringLiteral("Нет проверки обновлений (пакет sedmio-update).");
        Q_EMIT updatesChanged();
    });
    process->start(checker, {});
}

// ---- Обновление

void Updates::readUpgradeState()
{
    const QJsonObject state = readObject(upgradeState);
    const QString name = state.value(QStringLiteral("state")).toString();
    const bool wasUpgrading = m_upgrading;
    const auto snapshot = [this] {
        return QVariantList{m_upgrading, m_result, m_rebootNeeded, m_changedCount, m_log, m_progress, m_failText};
    };
    const QVariantList before = snapshot();

    if (name == QLatin1String("running")) {
        // Служба пропала, а итога нет — прервалось (выключили питание и т. п.).
        const qint64 started = state.value(QStringLiteral("started")).toInteger();
        if (QDateTime::currentSecsSinceEpoch() - started > 5 && !upgradeUnitAlive()) {
            m_upgrading = false;
            m_result = QStringLiteral("failed");
        } else {
            m_upgrading = true;
            m_result.clear();
        }
    } else {
        m_upgrading = false;
        m_result = name == QLatin1String("done") || name == QLatin1String("failed") ? name : QString();
        m_rebootNeeded = state.value(QStringLiteral("reboot")).toBool();
    }
    m_changedCount = state.value(QStringLiteral("changed")).toInt();

    // Журнал pacman: хвост, последняя строка, (n/m) — ход.
    QFile file(upgradeLog);
    if (file.open(QIODevice::ReadOnly)) {
        const qint64 tail = 96 * 1024;
        if (file.size() > tail)
            file.seek(file.size() - tail);
        QStringList lines = QString::fromUtf8(file.readAll()).split(QLatin1Char('\n'));
        if (lines.size() > 400)
            lines = lines.mid(lines.size() - 400);
        m_log = lines.join(QLatin1Char('\n')).trimmed();
        m_status.clear();
        for (auto it = lines.crbegin(); it != lines.crend(); ++it) {
            if (!it->trimmed().isEmpty()) {
                m_status = it->trimmed();
                break;
            }
        }
        // Ошибка pacman: «ошибка: …» и пояснения «:: …» под ней.
        m_failText.clear();
        if (m_result == QLatin1String("failed")) {
            for (qsizetype i = lines.size() - 1; i >= 0; --i) {
                const QString line = lines.at(i).trimmed();
                if (line.startsWith(QStringLiteral("ошибка:")) || line.startsWith(QLatin1String("error:"))) {
                    QStringList text{line.mid(line.indexOf(QLatin1Char(':')) + 1).trimmed()};
                    for (qsizetype j = i + 1; j < lines.size() && text.size() < 4; ++j) {
                        const QString more = lines.at(j).trimmed();
                        if (more.startsWith(QLatin1String("::")))
                            text << more.mid(2).trimmed();
                    }
                    m_failText = text.join(QLatin1Char('\n'));
                    break;
                }
            }
        }
        static const QRegularExpression step(QStringLiteral("^\\((\\d+)/(\\d+)\\)"));
        m_progress = -1;
        for (auto it = lines.crbegin(); it != lines.crend(); ++it) {
            const auto match = step.match(it->trimmed());
            if (match.hasMatch() && match.captured(2).toInt() > 0) {
                m_progress = qBound(0.0, match.captured(1).toDouble() / match.captured(2).toDouble(), 1.0);
                break;
            }
        }
    }

    m_poll.setInterval(m_upgrading ? 1000 : 3000);
    if (snapshot() != before)
        Q_EMIT upgradeChanged();

    if (wasUpgrading && !m_upgrading) {
        // Кончилось (итог — в карточке «Обновления»): списки заново.
        check();
        refresh();
    }
}

void Updates::upgrade()
{
    if (m_upgrading || busy())
        return;
    runHelper({QStringLiteral("upgrade")}, QStringLiteral("Начинаем обновление…"), [this](bool ok, const QString &) {
        if (ok) {
            m_result.clear();
            m_upgrading = true;
            Q_EMIT upgradeChanged();
            readUpgradeState();
        }
    });
}

void Updates::reboot()
{
    // Как кнопка «Перезагрузить» в Пуске: сеанс закроет программы.
    QDBusMessage call = QDBusMessage::createMethodCall(QStringLiteral("org.sedmio.SessionManager"), QStringLiteral("/Shutdown"),
                                                       QStringLiteral("org.kde.Shutdown"), QStringLiteral("logoutAndReboot"));
    if (QDBusConnection::sessionBus().call(call, QDBus::Block, 3000).type() == QDBusMessage::ReplyMessage)
        return;
    QDBusMessage logind = QDBusMessage::createMethodCall(QStringLiteral("org.freedesktop.login1"), QStringLiteral("/org/freedesktop/login1"),
                                                         QStringLiteral("org.freedesktop.login1.Manager"), QStringLiteral("Reboot"));
    logind << true;
    QDBusConnection::systemBus().call(logind, QDBus::NoBlock);
}

// ---- Снимки

void Updates::refresh()
{
    if (m_listing)
        return;
    m_listing = true;
    auto *process = new QProcess(this);
    connect(process, &QProcess::finished, this, [this, process](int code, QProcess::ExitStatus status) {
        process->deleteLater();
        m_listing = false;
        if (status == QProcess::NormalExit && code == 0) {
            parseSnapshots(process->readAllStandardOutput());
        } else {
            m_supported = false;
            m_unsupportedReason = code == 126 || code == 127 ? QStringLiteral("Не удалось посмотреть снимки: нет разрешения.")
                                                             : QString::fromUtf8(process->readAllStandardError()).trimmed();
            if (m_unsupportedReason.isEmpty())
                m_unsupportedReason = QStringLiteral("Не удалось посмотреть снимки.");
            m_snapshotsLoaded = true;
            Q_EMIT snapshotsChanged();
        }
    });
    connect(process, &QProcess::errorOccurred, this, [this, process](QProcess::ProcessError error) {
        if (error != QProcess::FailedToStart)
            return;
        process->deleteLater();
        m_listing = false;
        m_supported = false;
        m_unsupportedReason = QStringLiteral("Нет pkexec.");
        m_snapshotsLoaded = true;
        Q_EMIT snapshotsChanged();
    });
    process->start(QStringLiteral("pkexec"), {lister});
}

void Updates::parseSnapshots(const QByteArray &json)
{
    const QJsonObject data = QJsonDocument::fromJson(json).object();
    m_supported = data.value(QStringLiteral("supported")).toBool();
    m_unsupportedReason = data.value(QStringLiteral("reason")).toString();
    m_bootedSnapshot = data.value(QStringLiteral("booted")).toString();
    m_bootedTitle.clear();
    const QJsonObject restored = data.value(QStringLiteral("restored")).toObject();
    m_restoredTitle = restored.isEmpty() ? QString()
                                         : humanDate(QDateTime::fromString(restored.value(QStringLiteral("date")).toString(), Qt::ISODate));
    if (!restored.isEmpty() && m_restoredTitle.isEmpty())
        m_restoredTitle = restored.value(QStringLiteral("id")).toString();

    m_snapshots.clear();
    const QJsonArray list = data.value(QStringLiteral("snapshots")).toArray();
    for (const QJsonValue &v : list) {
        const QJsonObject o = v.toObject();
        const QString id = o.value(QStringLiteral("id")).toString();
        const QString kind = o.value(QStringLiteral("kind")).toString();
        const QString reason = o.value(QStringLiteral("reason")).toString();
        const int count = o.value(QStringLiteral("count")).toInt();
        QStringList packages;
        for (const QJsonValue &p : o.value(QStringLiteral("packages")).toArray())
            packages << p.toString();
        const QString title = humanDate(QDateTime::fromString(o.value(QStringLiteral("date")).toString(), Qt::ISODate));

        QString subtitle;
        if (kind == QLatin1String("manual")) {
            const QString note = o.value(QStringLiteral("note")).toString();
            subtitle = note.isEmpty() ? QStringLiteral("Сделан вручную") : note;
        } else if (kind == QLatin1String("restore")) {
            const QString target = humanDate(QDateTime::fromString(o.value(QStringLiteral("targetDate")).toString(), Qt::ISODate));
            subtitle = target.isEmpty() ? QStringLiteral("Перед возвратом к прежней версии")
                                        : QStringLiteral("Перед возвратом к снимку (%1)").arg(target);
        } else if (reason == QLatin1String("upgrade")) {
            subtitle = QStringLiteral("Перед обновлением системы");
            if (count > 0)
                subtitle += QStringLiteral(" · %1 %2").arg(count).arg(plural(count, QStringLiteral("пакет"), QStringLiteral("пакета"), QStringLiteral("пакетов")));
        } else {
            subtitle = count > 0 ? QStringLiteral("Перед изменением программ: ") + packageList(packages, count)
                                 : QStringLiteral("Перед изменением программ");
        }
        if (id == m_bootedSnapshot)
            m_bootedTitle = title;

        m_snapshots.append(QVariantMap{
            {QStringLiteral("id"), id},
            {QStringLiteral("title"), title.isEmpty() ? id : title},
            {QStringLiteral("subtitle"), subtitle},
            {QStringLiteral("kind"), kind},
            {QStringLiteral("booted"), id == m_bootedSnapshot},
            {QStringLiteral("bootMenu"), o.value(QStringLiteral("bootMenu")).toBool()},
        });
    }
    if (!m_bootedSnapshot.isEmpty() && m_bootedTitle.isEmpty())
        m_bootedTitle = m_bootedSnapshot;
    m_snapshotsLoaded = true;
    Q_EMIT snapshotsChanged();
}

void Updates::createSnapshot(const QString &note)
{
    runHelper({QStringLiteral("create"), note.trimmed()}, QStringLiteral("Сохраняем снимок…"), [this](bool ok, const QString &) {
        if (ok)
            finish(QStringLiteral("Снимок сохранён."), false);
        refresh();
    });
}

void Updates::removeSnapshot(const QString &id)
{
    runHelper({QStringLiteral("delete"), id}, QStringLiteral("Удаляем снимок…"), [this](bool ok, const QString &) {
        if (ok)
            finish(QStringLiteral("Снимок удалён."), false);
        refresh();
    });
}

void Updates::restore(const QString &id)
{
    runHelper({QStringLiteral("restore"), id}, QStringLiteral("Возвращаем систему к снимку — это может занять пару минут…"),
              [this](bool ok, const QString &) {
                  if (ok)
                      finish(QStringLiteral("Готово. Перезагрузите компьютер — система загрузится в выбранной версии."), false);
                  refresh();
              });
}

// ---- Помощник

void Updates::runHelper(const QStringList &args, const QString &busyText, const std::function<void(bool, const QString &)> &after)
{
    if (busy())
        return;
    m_busyText = busyText;
    m_message.clear();
    Q_EMIT busyChanged();
    auto *process = new QProcess(this);
    connect(process, &QProcess::finished, this, [this, process, after](int code, QProcess::ExitStatus status) {
        process->deleteLater();
        m_busyText.clear();
        const QString error = QString::fromUtf8(process->readAllStandardError()).trimmed();
        const bool ok = status == QProcess::NormalExit && code == 0;
        if (status != QProcess::NormalExit)
            finish(QStringLiteral("Помощник обновлений завершился с ошибкой."), true);
        else if (code == 126 || code == 127)
            finish(QStringLiteral("Не сделано: не подтверждено паролем."), true);
        else if (code != 0)
            finish(error.isEmpty() ? QStringLiteral("Не получилось.") : error, true);
        else
            Q_EMIT busyChanged();
        after(ok, error);
    });
    connect(process, &QProcess::errorOccurred, this, [this, process](QProcess::ProcessError error) {
        if (error != QProcess::FailedToStart)
            return;
        process->deleteLater();
        m_busyText.clear();
        finish(QStringLiteral("Не получилось запустить pkexec."), true);
    });
    process->start(QStringLiteral("pkexec"), QStringList{helper} + args);
}

void Updates::finish(const QString &message, bool error)
{
    m_message = message;
    m_messageIsError = error;
    Q_EMIT busyChanged();
}

void Updates::clearMessage()
{
    if (m_message.isEmpty())
        return;
    m_message.clear();
    Q_EMIT busyChanged();
}
