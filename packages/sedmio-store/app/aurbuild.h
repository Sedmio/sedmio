#pragma once

#include <QObject>
#include <QPointer>
#include <QProcess>
#include <QStringList>
#include <QVariantMap>

#include <functional>

// Собрать и поставить пакеты AUR по плану просмотра (AurReview::plan()):
//
//  1. Нужное из репозиториев — pkexec store-helper install-deps (как
//     зависимости), base-devel — если его нет.
//  2. Каждый пакет: сверить отпечаток просмотренной папки, скопировать её
//     в ~/.cache/sedmio-store/aur/build/<base> и собрать там makepkg от
//     пользователя (не root), потоков не больше 8, с nice. Неизвестный
//     ключ PGP автора исходников — берём с сервера ключей и пробуем ещё.
//  3. Собранное — pkexec store-helper install-files (помощник сначала
//     копирует файлы к себе, чтобы их не подменили по дороге). Цели — явно,
//     зависимости — «как зависимости».
class AurBuild : public QObject
{
    Q_OBJECT

public:
    explicit AurBuild(const QVariantMap &plan, QObject *parent = nullptr);
    void start();
    void cancel();

Q_SIGNALS:
    void progress(double fraction, const QString &text);
    // Строки makepkg и pacman — в журнал задания.
    void output(const QString &text);
    // error пусто — готово; code 3 — занято, 4 — базы устарели, -1 — пароль не введён.
    void finished(const QString &error, int code);

private:
    void installRepoDeps();
    void buildNext();
    void makepkg(const QString &base, bool retried);
    void installBuilt(const QString &base, const QStringList &files);
    void fail(const QString &error, int code = 0);
    QString buildDir(const QString &base) const;
    double share() const;
    void run(const QString &program, const QStringList &args, std::function<void(int, const QString &)> done, const QString &workdir = {},
             const QProcessEnvironment &env = QProcessEnvironment::systemEnvironment());

    QStringList m_targets;
    QStringList m_names;            // все пакеты к установке
    QStringList m_bases;            // в порядке сборки
    QVariantMap m_baseInfo;         // base → {dir, hash, maintainer, vcs}
    QStringList m_repoDeps;
    int m_index = 0;
    bool m_cancelled = false;
    QPointer<QProcess> m_process;
};
