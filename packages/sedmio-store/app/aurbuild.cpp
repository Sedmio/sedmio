#include "aurbuild.h"
#include "aur.h"
#include "aurreview.h"

#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QThread>

namespace
{
const QString helper = QStringLiteral("/usr/lib/sedmio/store-helper");

QString lastLines(const QString &text, int n)
{
    QStringList lines = text.trimmed().split(u'\n');
    return lines.mid(qMax(0, lines.size() - n)).join(u'\n');
}

// Копия папки пакета: обычные файлы и ссылки внутри неё как есть.
bool copyTree(const QString &from, const QString &to)
{
    QDir().mkpath(to);
    QDirIterator it(from, QDir::Files | QDir::Dirs | QDir::Hidden | QDir::NoDotAndDotDot | QDir::System, QDirIterator::Subdirectories);
    while (it.hasNext()) {
        const QFileInfo info(it.next());
        const QString target = to + u'/' + QDir(from).relativeFilePath(info.filePath());
        if (info.isSymLink()) {
            if (!QFile::link(info.symLinkTarget(), target))
                return false;
        } else if (info.isDir()) {
            QDir().mkpath(target);
        } else if (!QFile::copy(info.filePath(), target)) {
            return false;
        }
    }
    return true;
}

// Ошибка помощника: «ERROR <код> <текст>».
std::pair<QString, int> helperError(const QString &out)
{
    static const QRegularExpression error(QStringLiteral("ERROR (\\d+) (.*)"));
    const auto m = error.match(out);
    return m.hasMatch() ? std::pair{m.captured(2), m.captured(1).toInt()} : std::pair{lastLines(out, 2), 0};
}
} // namespace

AurBuild::AurBuild(const QVariantMap &plan, QObject *parent)
    : QObject(parent)
    , m_targets(plan.value(QStringLiteral("targets")).toStringList())
    , m_baseInfo(plan.value(QStringLiteral("bases")).toMap())
    , m_repoDeps(plan.value(QStringLiteral("repoDeps")).toStringList())
{
    for (const QVariant &v : plan.value(QStringLiteral("order")).toList()) {
        const QVariantMap entry = v.toMap();
        m_names << entry.value(QStringLiteral("name")).toString();
        const QString base = entry.value(QStringLiteral("base")).toString();
        if (!m_bases.contains(base))
            m_bases << base;
    }
}

QString AurBuild::buildDir(const QString &base) const
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericCacheLocation) + QStringLiteral("/sedmio-store/aur/build/") + base;
}

double AurBuild::share() const
{
    return 0.85 / qMax(1, int(m_bases.size()));
}

void AurBuild::run(const QString &program, const QStringList &args, std::function<void(int, const QString &)> done, const QString &workdir,
                   const QProcessEnvironment &env)
{
    auto *process = new QProcess(this);
    m_process = process;
    process->setProcessChannelMode(QProcess::MergedChannels);
    process->setProcessEnvironment(env);
    if (!workdir.isEmpty())
        process->setWorkingDirectory(workdir);
    auto output = std::make_shared<QString>();
    auto pending = std::make_shared<QString>();
    connect(process, &QProcess::readyRead, this, [this, process, output, pending] {
        *pending += QString::fromUtf8(process->readAll());
        qsizetype end;
        QString lines;
        while ((end = pending->indexOf(u'\n')) >= 0) {
            QString line = pending->left(end);
            pending->remove(0, end + 1);
            // Помощник: «LOG …» — строка pacman, «STEP …» — что делает.
            if (line.startsWith(QLatin1String("LOG ")))
                line = line.mid(4);
            else if (line.startsWith(QLatin1String("STEP ")) || line.startsWith(QLatin1String("PROGRESS ")))
                continue;
            *output += line + u'\n';
            lines += line + u'\n';
            if (line.startsWith(QLatin1String("==> Retrieving sources")))
                Q_EMIT progress(-1, QStringLiteral("Скачиваю исходники"));
            else if (line.startsWith(QLatin1String("==> Starting build()")))
                Q_EMIT progress(-1, QStringLiteral("Собираю — это может быть долго"));
            else if (line.startsWith(QLatin1String("==> Entering fakeroot")))
                Q_EMIT progress(-1, QStringLiteral("Упаковываю"));
        }
        if (!lines.isEmpty())
            Q_EMIT this->output(lines);
    });
    connect(process, &QProcess::finished, this, [this, process, output, pending, done](int code, QProcess::ExitStatus status) {
        process->deleteLater();
        if (!pending->isEmpty()) {
            *output += *pending;
            Q_EMIT this->output(*pending + u'\n');
        }
        if (m_cancelled)
            return;
        done(status == QProcess::NormalExit ? code : -2, *output);
    });
    connect(process, &QProcess::errorOccurred, this, [this, process, program](QProcess::ProcessError error) {
        if (error != QProcess::FailedToStart)
            return;
        process->deleteLater();
        fail(QStringLiteral("Не запускается %1").arg(program));
    });
    process->start(program, args);
}

void AurBuild::start()
{
    if (m_bases.isEmpty()) {
        fail(QStringLiteral("Нечего собирать — откройте просмотр ещё раз"));
        return;
    }
    installRepoDeps();
}

void AurBuild::cancel()
{
    m_cancelled = true;
    if (m_process)
        m_process->kill();
    Q_EMIT finished(QStringLiteral("Отменено"), -1);
}

void AurBuild::fail(const QString &error, int code)
{
    if (m_cancelled)
        return;
    m_cancelled = true;
    Q_EMIT finished(error, code);
}

// ---- 1. Нужное из репозиториев

void AurBuild::installRepoDeps()
{
    if (m_repoDeps.isEmpty()) {
        buildNext();
        return;
    }
    Q_EMIT progress(0.05, QStringLiteral("Ставлю нужное для сборки: ") + m_repoDeps.mid(0, 4).join(QStringLiteral(", "))
                              + (m_repoDeps.size() > 4 ? QStringLiteral("…") : QString()));
    run(QStringLiteral("pkexec"), QStringList{helper, QStringLiteral("install-deps")} + m_repoDeps, [this](int code, const QString &out) {
        if (code == 126 || code == 127) {
            fail(QStringLiteral("Пароль не введён"), -1);
            return;
        }
        if (code != 0) {
            const auto [error, errorCode] = helperError(out);
            fail(error, errorCode);
            return;
        }
        buildNext();
    });
}

// ---- 2. Сборка

void AurBuild::buildNext()
{
    if (m_cancelled)
        return;
    if (m_index >= m_bases.size()) {
        m_cancelled = true; // больше ничего не шлём
        Q_EMIT finished({}, 0);
        return;
    }
    const QString base = m_bases.at(m_index);
    const QVariantMap info = m_baseInfo.value(base).toMap();
    const QString reviewed = info.value(QStringLiteral("dir")).toString();
    // Собираем ровно то, что человек прочитал.
    if (reviewed != AurReview::reviewDir(base) || AurReview::treeHash(reviewed) != info.value(QStringLiteral("hash")).toString().toLatin1()) {
        fail(QStringLiteral("Файлы %1 изменились после просмотра — откройте просмотр ещё раз").arg(base));
        return;
    }
    const QString dir = buildDir(base);
    QDir(dir).removeRecursively();
    if (!copyTree(reviewed, dir)) {
        fail(QStringLiteral("Не скопировать %1 для сборки").arg(base));
        return;
    }
    makepkg(base, false);
}

void AurBuild::makepkg(const QString &base, bool retried)
{
    Q_EMIT progress(0.12 + m_index * share() + share() * 0.1, QStringLiteral("Собираю %1").arg(base));
    const QString dir = buildDir(base);
    QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
    env.insert(QStringLiteral("LC_ALL"), QStringLiteral("C"));
    // Не больше 8 потоков: сборка не должна съесть всю память.
    env.insert(QStringLiteral("MAKEFLAGS"), QStringLiteral("-j%1").arg(qBound(1, QThread::idealThreadCount(), 8)));
    env.insert(QStringLiteral("PKGDEST"), dir + QStringLiteral("/out"));
    QDir().mkpath(dir + QStringLiteral("/out"));
    run(QStringLiteral("nice"), {QStringLiteral("-n"), QStringLiteral("10"), QStringLiteral("makepkg"), QStringLiteral("-f"), QStringLiteral("--noconfirm")},
        [this, base, dir, env, retried](int code, const QString &out) {
            QFile log(dir + QStringLiteral("/build.log"));
            if (log.open(QIODevice::WriteOnly))
                log.write(out.toUtf8());
            if (code != 0) {
                // Подпись исходников ключом, которого у нас нет, — взять его.
                static const QRegularExpression unknownKey(QStringLiteral("unknown public key ([0-9A-Fa-f]{8,})"));
                const auto m = unknownKey.match(out);
                if (m.hasMatch() && !retried) {
                    Q_EMIT progress(-1, QStringLiteral("Беру ключ PGP автора"));
                    run(QStringLiteral("gpg"), {QStringLiteral("--recv-keys"), m.captured(1)}, [this, base](int, const QString &) {
                        makepkg(base, true);
                    });
                    return;
                }
                static const QRegularExpression error(QStringLiteral("==> ERROR: (.*)"));
                const auto e = error.match(out);
                fail(QStringLiteral("Сборка %1 не удалась: %2").arg(base, e.hasMatch() ? e.captured(1) : lastLines(out, 1)));
                return;
            }
            // Какие файлы получились: --packagelist — в порядке pkgname из .SRCINFO.
            run(QStringLiteral("makepkg"), {QStringLiteral("--packagelist")}, [this, base, dir](int, const QString &list) {
                QStringList names;
                QFile srcinfo(dir + QStringLiteral("/.SRCINFO"));
                if (srcinfo.open(QIODevice::ReadOnly)) {
                    for (const QByteArray &line : srcinfo.readAll().split('\n')) {
                        const QByteArray t = line.trimmed();
                        if (t.startsWith("pkgname = "))
                            names << QString::fromUtf8(t.mid(10));
                    }
                }
                const QStringList files = list.split(u'\n', Qt::SkipEmptyParts);
                // Из разделённого пакета ставим только то, что нужно.
                QStringList wanted;
                for (qsizetype i = 0; i < files.size() && i < names.size(); ++i) {
                    if (m_names.contains(names.at(i)) && QFile::exists(files.at(i)))
                        wanted << files.at(i);
                }
                if (wanted.isEmpty()) {
                    fail(QStringLiteral("После сборки %1 не нашлось пакета").arg(base));
                    return;
                }
                installBuilt(base, wanted);
            }, dir, env);
        },
        dir, env);
}

// ---- 3. Установка собранного

void AurBuild::installBuilt(const QString &base, const QStringList &files)
{
    Q_EMIT progress(0.12 + m_index * share() + share() * 0.9, QStringLiteral("Устанавливаю %1").arg(base));
    // Пакеты, которые просили, — явно; их зависимости — «как зависимости»
    // (удалятся вместе с тем, кому нужны). У обновления причина установки
    // у pacman сохраняется сама.
    QStringList explicitFiles, depFiles;
    QStringList installedNames;
    for (const QString &file : files) {
        const QString fileName = QFileInfo(file).fileName();
        const auto target = std::find_if(m_targets.cbegin(), m_targets.cend(), [&fileName](const QString &t) {
            // имя-версия-выпуск-арх.pkg.tar.zst: имя — всё до трёх последних «-».
            return fileName.section(u'-', 0, -4) == t;
        });
        (target != m_targets.cend() ? explicitFiles : depFiles) << file;
        installedNames << fileName.section(u'-', 0, -4);
    }
    auto install = [this](const QStringList &list, bool asDeps, std::function<void()> next) {
        if (list.isEmpty()) {
            next();
            return;
        }
        QStringList args{helper, QStringLiteral("install-files")};
        if (asDeps)
            args << QStringLiteral("--asdeps");
        args << list;
        run(QStringLiteral("pkexec"), args, [this, next](int code, const QString &out) {
            if (code == 126 || code == 127) {
                fail(QStringLiteral("Пароль не введён"), -1);
                return;
            }
            if (code != 0) {
                const auto [error, errorCode] = helperError(out);
                fail(error, errorCode);
                return;
            }
            next();
        });
    };
    install(depFiles, true, [this, install, explicitFiles, installedNames, base] {
        install(explicitFiles, false, [this, installedNames, base] {
            const QVariantMap info = m_baseInfo.value(base).toMap();
            for (const QString &name : installedNames)
                Aur::instance()->remember(name, info.value(QStringLiteral("maintainer")).toString(), info.value(QStringLiteral("vcs")).toMap());
            // Сборочная папка больше не нужна (журнал — в задании).
            QDir(buildDir(base)).removeRecursively();
            ++m_index;
            buildNext();
        });
    });
}
