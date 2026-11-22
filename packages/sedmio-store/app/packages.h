#pragma once

#include <QFileSystemWatcher>
#include <QHash>
#include <QObject>
#include <QTimer>

// Что установлено и что есть в репозиториях — прямо из pacman и flatpak,
// а не из каталога AppStream: каталог (archlinux-appstream-data) отстаёт
// от баз pacman, и Discover на этом спотыкался («не удалось найти пакет»).
// Пакет, которого нет в базе синхронизации, магазин не предлагает.
//
// Обновляется сам: pacman или flatpak что-то поставил или снял (хоть из
// терминала) — через полсекунды списки перечитываются.
class Packages : public QObject
{
    Q_OBJECT

public:
    struct Flatpak {
        QString id;         // как в flatpak (org.mozilla.firefox)
        QString branch;     // stable
        QString origin;     // flathub
        QString version;    // из метаданных программы
        QString name;
        bool user = true;   // установка пользователя (без пароля)
        qint64 size = 0;    // на диске
    };

    explicit Packages(QObject *parent = nullptr);

    bool ready() const { return m_pacmanReady && m_flatpakReady; }
    void refresh();

    // pacman: имя → версия.
    const QHash<QString, QString> &installed() const { return m_installed; }
    const QHash<QString, QString> &sync() const { return m_sync; }
    QString repo(const QString &package) const { return m_repo.value(package); }
    // Базы синхронизации прочитаны (иначе доступность не проверить).
    bool hasSync() const { return !m_sync.isEmpty(); }

    // flatpak: id строчными → программа.
    const QHash<QString, Flatpak> &flatpaks() const { return m_flatpaks; }

Q_SIGNALS:
    void changed();

private:
    void readPacman();
    void readFlatpak();
    void watch();

    QHash<QString, QString> m_installed;
    QHash<QString, QString> m_sync;
    QHash<QString, QString> m_repo;
    QHash<QString, Flatpak> m_flatpaks;
    bool m_pacmanReady = false;
    bool m_flatpakReady = false;
    bool m_pacmanBusy = false;
    bool m_flatpakBusy = false;
    QFileSystemWatcher m_watcher;
    QTimer m_debounce;
};
