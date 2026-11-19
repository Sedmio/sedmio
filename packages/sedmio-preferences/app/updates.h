#pragma once

#include <QDateTime>
#include <QObject>
#include <QQmlEngine>
#include <QTimer>
#include <QVariantList>

#include <functional>

class QProcess;

// «Обновление»: есть ли обновления, обновить, снимки системы. Работа —
// пакет sedmio-update:
//   /usr/lib/sedmio/update-check — проверка от пользователя, итог в
//     ~/.local/state/sedmio/updates.json (его же пишет проверка по таймеру);
//   pkexec /usr/lib/sedmio/update-helper — обновить (служба sedmio-upgrade,
//     ход — /run/sedmio-update/upgrade.{json,log}), сделать, удалить снимок,
//     вернуть систему к снимку;
//   pkexec /usr/lib/sedmio/update-snapshots — список снимков, без пароля.
class Updates : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    // Снимки: можно ли (система на btrfs, подтом @) и почему нет.
    Q_PROPERTY(bool supported READ supported NOTIFY snapshotsChanged)
    Q_PROPERTY(QString unsupportedReason READ unsupportedReason NOTIFY snapshotsChanged)
    Q_PROPERTY(bool snapshotsLoaded READ snapshotsLoaded NOTIFY snapshotsChanged)
    // [{id, title, subtitle, kind, booted, bootMenu}], новые сверху.
    Q_PROPERTY(QVariantList snapshots READ snapshots NOTIFY snapshotsChanged)
    // Система загружена из снимка (меню загрузки): когда он сделан.
    Q_PROPERTY(QString bootedSnapshot READ bootedSnapshot NOTIFY snapshotsChanged)
    Q_PROPERTY(QString bootedTitle READ bootedTitle NOTIFY snapshotsChanged)
    // Система возвращена к снимку, ждёт перезагрузки: к какому.
    Q_PROPERTY(QString restoredTitle READ restoredTitle NOTIFY snapshotsChanged)

    // Проверка обновлений.
    Q_PROPERTY(bool checking READ checking NOTIFY updatesChanged)
    Q_PROPERTY(QString lastCheck READ lastCheck NOTIFY updatesChanged)
    Q_PROPERTY(QString checkError READ checkError NOTIFY updatesChanged)
    Q_PROPERTY(QVariantList updates READ updates NOTIFY updatesChanged)

    // Обновление: идёт ли, ход (0…1, -1 — неизвестно), последняя строка и
    // журнал pacman, итог ("" | "done" | "failed"), нужна ли перезагрузка.
    Q_PROPERTY(bool upgrading READ upgrading NOTIFY upgradeChanged)
    Q_PROPERTY(qreal progress READ progress NOTIFY upgradeChanged)
    Q_PROPERTY(QString status READ status NOTIFY upgradeChanged)
    Q_PROPERTY(QString log READ log NOTIFY upgradeChanged)
    Q_PROPERTY(QString result READ result NOTIFY upgradeChanged)
    Q_PROPERTY(bool rebootNeeded READ rebootNeeded NOTIFY upgradeChanged)
    // Не получилось: строки ошибки pacman и сколько пакетов всё же изменилось.
    Q_PROPERTY(QString failText READ failText NOTIFY upgradeChanged)
    Q_PROPERTY(int changedCount READ changedCount NOTIFY upgradeChanged)

    // Ждём пароль или помощника; итог последнего действия.
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(QString busyText READ busyText NOTIFY busyChanged)
    Q_PROPERTY(QString message READ message NOTIFY busyChanged)
    Q_PROPERTY(bool messageIsError READ messageIsError NOTIFY busyChanged)

public:
    explicit Updates(QObject *parent = nullptr);

    bool supported() const { return m_supported; }
    QString unsupportedReason() const { return m_unsupportedReason; }
    bool snapshotsLoaded() const { return m_snapshotsLoaded; }
    QVariantList snapshots() const { return m_snapshots; }
    QString bootedSnapshot() const { return m_bootedSnapshot; }
    QString bootedTitle() const { return m_bootedTitle; }
    QString restoredTitle() const { return m_restoredTitle; }

    bool checking() const { return m_checking; }
    QString lastCheck() const;
    QString checkError() const { return m_checkError; }
    QVariantList updates() const { return m_updates; }

    bool upgrading() const { return m_upgrading; }
    qreal progress() const { return m_progress; }
    QString status() const { return m_status; }
    QString log() const { return m_log; }
    QString result() const { return m_result; }
    bool rebootNeeded() const { return m_rebootNeeded; }
    QString failText() const { return m_failText; }
    int changedCount() const { return m_changedCount; }

    bool busy() const { return !m_busyText.isEmpty(); }
    QString busyText() const { return m_busyText; }
    QString message() const { return m_message; }
    bool messageIsError() const { return m_messageIsError; }

    Q_INVOKABLE void refresh();
    Q_INVOKABLE void check();
    Q_INVOKABLE void upgrade();
    Q_INVOKABLE void createSnapshot(const QString &note);
    Q_INVOKABLE void removeSnapshot(const QString &id);
    Q_INVOKABLE void restore(const QString &id);
    Q_INVOKABLE void reboot();
    Q_INVOKABLE void clearMessage();

    // Дата снимка или проверки по-человечески: «сегодня, 14:03», «20 ноября, 14:03».
    static QString humanDate(const QDateTime &when);

Q_SIGNALS:
    void snapshotsChanged();
    void updatesChanged();
    void upgradeChanged();
    void busyChanged();

private:
    void readCheckState();
    void readUpgradeState();
    void parseSnapshots(const QByteArray &json);
    // pkexec update-helper <args>; after(успех, вывод ошибки).
    void runHelper(const QStringList &args, const QString &busyText, const std::function<void(bool, const QString &)> &after);
    void finish(const QString &message, bool error);

    bool m_supported = false;
    QString m_unsupportedReason;
    bool m_snapshotsLoaded = false;
    QVariantList m_snapshots;
    QString m_bootedSnapshot;
    QString m_bootedTitle;
    QString m_restoredTitle;
    bool m_listing = false;

    bool m_checking = false;
    qint64 m_checked = 0;
    QString m_checkError;
    QVariantList m_updates;

    bool m_upgrading = false;
    qreal m_progress = -1;
    QString m_status;
    QString m_log;
    QString m_result;
    bool m_rebootNeeded = false;
    QString m_failText;
    int m_changedCount = 0;
    qint64 m_upgradeStarted = 0;
    QTimer m_poll;

    QString m_busyText;
    QString m_message;
    bool m_messageIsError = false;
};
