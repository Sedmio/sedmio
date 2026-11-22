#pragma once

#include <QHash>
#include <QObject>
#include <QPointer>
#include <QProcess>
#include <QSet>
#include <QStringList>
#include <QVariantMap>

// Собрать и поставить пакет из AUR — как yay, но без терминала:
//
//  1. Какие зависимости нужны (AUR RPC + pacman -T): из репозиториев —
//     ставим сразу (pkexec store-helper install-deps), из AUR — собираем
//     раньше самого пакета.
//  2. Каждый пакет: архив с AUR → ~/.cache/sedmio-store/aur/<base>,
//     makepkg от пользователя (не root), потоков не больше 8, с nice.
//     Неизвестный ключ PGP автора исходников — берём с сервера ключей
//     и пробуем ещё раз.
//  3. Собранное — pkexec store-helper install-files (pacman -U; помощник
//     сначала копирует файлы к себе, чтобы их не подменили по дороге).
//
// PKGBUILD человек смотрит до этого (страница AUR в QML): сборка — это
// чужой скрипт на своём компьютере.
class AurBuild : public QObject
{
    Q_OBJECT

public:
    explicit AurBuild(const QString &name, QObject *parent = nullptr);
    void start();
    void cancel();

Q_SIGNALS:
    void progress(double fraction, const QString &text);
    // error пусто — готово; code 3 — занято, -1 — пароль не введён.
    void finished(const QString &error, int code);

private:
    struct Package {
        QString name;
        QString base;
        QString version;
        QStringList depends;
    };

    void resolve(const QStringList &names);
    void checkMissing(const QStringList &deps, std::function<void(const QStringList &missing)> done);
    void classify(const QStringList &missing);
    void installRepoDeps();
    void buildNext();
    void download(const Package &package);
    void makepkg(const Package &package, bool retried);
    void installBuilt(const Package &package, const QStringList &files);
    void fail(const QString &error, int code = 0);
    QString dirOf(const QString &base) const;
    void run(const QString &program, const QStringList &args, std::function<void(int, const QString &)> done, const QString &workdir = {},
             const QProcessEnvironment &env = QProcessEnvironment::systemEnvironment());

    QString m_name;
    QHash<QString, Package> m_aur;   // имя → сведения
    QStringList m_order;             // в каком порядке собирать (зависимости раньше)
    QStringList m_repoDeps;          // поставить из репозиториев
    QStringList m_pending;           // ещё не разобранные зависимости
    QSet<QString> m_seen;
    int m_index = 0;
    bool m_cancelled = false;
    QPointer<QProcess> m_process;
};
