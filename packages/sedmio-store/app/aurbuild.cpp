#include "aurbuild.h"
#include "aur.h"

#include <QDir>
#include <QFile>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QThread>

namespace
{
const QString helper = QStringLiteral("/usr/lib/sedmio/store-helper");
const int maxPackages = 30;

// «python>=3.10» → «python».
QString bareName(const QString &dep)
{
    static const QRegularExpression op(QStringLiteral("[<>=].*$"));
    return QString(dep).remove(op).trimmed();
}

QString lastLines(const QString &text, int n)
{
    QStringList lines = text.trimmed().split(u'\n');
    return lines.mid(qMax(0, lines.size() - n)).join(u'\n');
}
} // namespace

AurBuild::AurBuild(const QString &name, QObject *parent)
    : QObject(parent)
    , m_name(name)
{
}

QString AurBuild::dirOf(const QString &base) const
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericCacheLocation) + QStringLiteral("/sedmio-store/aur/") + base;
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
    connect(process, &QProcess::readyRead, this, [this, process, output] {
        const QString chunk = QString::fromUtf8(process->readAll());
        *output += chunk;
        // Что делает makepkg: «==> Starting build()…».
        for (const QString &line : chunk.split(u'\n')) {
            if (line.startsWith(QLatin1String("==> Retrieving sources")))
                Q_EMIT progress(-1, QStringLiteral("Скачиваю исходники"));
            else if (line.startsWith(QLatin1String("==> Starting build()")))
                Q_EMIT progress(-1, QStringLiteral("Собираю — это может быть долго"));
            else if (line.startsWith(QLatin1String("==> Entering fakeroot")))
                Q_EMIT progress(-1, QStringLiteral("Упаковываю"));
        }
    });
    connect(process, &QProcess::finished, this, [this, process, output, done](int code, QProcess::ExitStatus status) {
        process->deleteLater();
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
    Q_EMIT progress(0.02, QStringLiteral("Смотрю зависимости"));
    m_seen.insert(m_name);
    resolve({m_name});
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

// ---- 1. Зависимости

void AurBuild::resolve(const QStringList &names)
{
    m_pending << names;
    Aur::instance()->infoMany(names, [this, names](const QList<QVariantMap> &list, const QString &error) {
        if (m_cancelled)
            return;
        if (!error.isEmpty()) {
            fail(error);
            return;
        }
        QStringList deps;
        QSet<QString> found;
        for (const QVariantMap &info : list) {
            Package p;
            p.name = info.value(QStringLiteral("name")).toString();
            p.base = info.value(QStringLiteral("base")).toString();
            p.version = info.value(QStringLiteral("version")).toString();
            for (const QString &dep : info.value(QStringLiteral("depends")).toStringList() + info.value(QStringLiteral("makeDepends")).toStringList()) {
                const QString bare = bareName(dep);
                if (!bare.isEmpty() && !p.depends.contains(bare))
                    p.depends << bare;
            }
            m_aur.insert(p.name, p);
            found.insert(p.name);
            for (const QString &dep : std::as_const(p.depends)) {
                if (!m_seen.contains(dep)) {
                    m_seen.insert(dep);
                    deps << dep;
                }
            }
        }
        for (const QString &name : names) {
            if (!found.contains(name)) {
                fail(name == m_name ? QStringLiteral("Пакета %1 нет в AUR").arg(name)
                                    : QStringLiteral("Зависимость %1 не нашлась ни в репозиториях, ни в AUR").arg(name));
                return;
            }
        }
        if (m_aur.size() > maxPackages) {
            fail(QStringLiteral("Слишком много пакетов AUR в зависимостях (больше %1) — такое лучше ставить вручную").arg(maxPackages));
            return;
        }
        for (const QString &name : names)
            m_pending.removeOne(name);
        // Всё ли из зависимостей уже стоит (с учётом provides — pacman -T).
        checkMissing(deps, [this](const QStringList &missing) { classify(missing); });
    });
}

void AurBuild::checkMissing(const QStringList &deps, std::function<void(const QStringList &)> done)
{
    if (deps.isEmpty()) {
        done({});
        return;
    }
    run(QStringLiteral("pacman"), QStringList{QStringLiteral("-T"), QStringLiteral("--")} + deps, [done](int, const QString &out) {
        done(out.split(u'\n', Qt::SkipEmptyParts));
    });
}

void AurBuild::classify(const QStringList &missing)
{
    if (missing.isEmpty()) {
        if (m_pending.isEmpty())
            installRepoDeps();
        return;
    }
    // Чего нет в репозиториях (pacman -Sp сам найдёт и того, кто «provides»),
    // — ищем в AUR.
    QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
    env.insert(QStringLiteral("LC_ALL"), QStringLiteral("C"));
    QStringList args{QStringLiteral("-Sp"), QStringLiteral("--print-format"), QStringLiteral("%n"), QStringLiteral("--")};
    run(QStringLiteral("pacman"), args + missing, [this, missing](int code, const QString &out) {
        static const QRegularExpression notFound(QStringLiteral("target not found: (\\S+)"));
        QStringList aur;
        for (auto it = notFound.globalMatch(out); it.hasNext();)
            aur << it.next().captured(1);
        if (code != 0 && aur.isEmpty()) {
            fail(QStringLiteral("Не сходятся зависимости: ") + lastLines(out, 2));
            return;
        }
        for (const QString &name : missing) {
            if (!aur.contains(name) && !m_repoDeps.contains(name))
                m_repoDeps << name;
        }
        if (!aur.isEmpty())
            resolve(aur);
        else if (m_pending.isEmpty())
            installRepoDeps();
    }, {}, env);
}

// ---- 2. Зависимости из репозиториев

void AurBuild::installRepoDeps()
{
    // Порядок сборки: зависимости из AUR — раньше тех, кому нужны.
    QSet<QString> visited;
    std::function<void(const QString &)> visit = [&](const QString &name) {
        if (visited.contains(name) || !m_aur.contains(name))
            return;
        visited.insert(name);
        for (const QString &dep : m_aur.value(name).depends)
            visit(dep);
        m_order << name;
    };
    visit(m_name);

    // Без base-devel (gcc, make, fakeroot…) makepkg ничего не соберёт.
    checkMissing({QStringLiteral("base-devel")}, [this](const QStringList &missing) {
        QStringList deps = m_repoDeps;
        if (!missing.isEmpty())
            deps.prepend(QStringLiteral("base-devel"));
        if (deps.isEmpty()) {
            buildNext();
            return;
        }
        Q_EMIT progress(0.08, QStringLiteral("Ставлю нужное для сборки: ") + deps.mid(0, 4).join(QStringLiteral(", "))
                                  + (deps.size() > 4 ? QStringLiteral("…") : QString()));
        run(QStringLiteral("pkexec"), QStringList{helper, QStringLiteral("install-deps")} + deps, [this](int code, const QString &out) {
            if (code == 126 || code == 127) {
                fail(QStringLiteral("Пароль не введён"), -1);
                return;
            }
            if (code != 0) {
                static const QRegularExpression error(QStringLiteral("ERROR (\\d+) (.*)"));
                const auto m = error.match(out);
                fail(m.hasMatch() ? m.captured(2) : lastLines(out, 2), m.hasMatch() ? m.captured(1).toInt() : 0);
                return;
            }
            buildNext();
        });
    });
}

// ---- 3. Сборка

void AurBuild::buildNext()
{
    if (m_cancelled)
        return;
    if (m_index >= m_order.size()) {
        m_cancelled = true; // больше ничего не шлём
        Q_EMIT finished({}, 0);
        return;
    }
    download(m_aur.value(m_order.at(m_index)));
}

void AurBuild::download(const Package &package)
{
    const double share = 0.85 / qMax(1, int(m_order.size()));
    Q_EMIT progress(0.12 + m_index * share, QStringLiteral("Скачиваю %1 из AUR").arg(package.base));
    const QString dir = dirOf(package.base);
    QDir(dir).removeRecursively();
    QDir().mkpath(dir);
    auto *network = new QNetworkAccessManager(this);
    QNetworkRequest request(QUrl(QStringLiteral("https://aur.archlinux.org/cgit/aur.git/snapshot/%1.tar.gz").arg(package.base)));
    request.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("sedmio-store"));
    QNetworkReply *reply = network->get(request);
    connect(reply, &QNetworkReply::finished, this, [this, reply, network, package, dir] {
        reply->deleteLater();
        network->deleteLater();
        if (m_cancelled)
            return;
        if (reply->error() != QNetworkReply::NoError) {
            fail(QStringLiteral("Не скачался %1 из AUR — проверьте интернет").arg(package.base));
            return;
        }
        const QString archive = dir + QStringLiteral(".tar.gz");
        QFile file(archive);
        if (!file.open(QIODevice::WriteOnly) || file.write(reply->readAll()) < 0) {
            fail(QStringLiteral("Не записать %1").arg(archive));
            return;
        }
        file.close();
        // В архиве — папка <base>/ с PKGBUILD и .SRCINFO.
        run(QStringLiteral("bsdtar"), {QStringLiteral("-xf"), archive, QStringLiteral("-C"), QFileInfo(dir).path()},
            [this, package, archive](int code, const QString &out) {
                QFile::remove(archive);
                if (code != 0) {
                    fail(QStringLiteral("Архив %1 не распаковался: %2").arg(package.base, lastLines(out, 1)));
                    return;
                }
                makepkg(package, false);
            });
    });
}

void AurBuild::makepkg(const Package &package, bool retried)
{
    const double share = 0.85 / qMax(1, int(m_order.size()));
    Q_EMIT progress(0.12 + m_index * share + share * 0.1, QStringLiteral("Собираю %1").arg(package.base));
    const QString dir = dirOf(package.base);
    QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
    env.insert(QStringLiteral("LC_ALL"), QStringLiteral("C"));
    // Не больше 8 потоков: сборка не должна съесть всю память.
    env.insert(QStringLiteral("MAKEFLAGS"), QStringLiteral("-j%1").arg(qBound(1, QThread::idealThreadCount(), 8)));
    env.insert(QStringLiteral("PKGDEST"), dir + QStringLiteral("/out"));
    QDir().mkpath(dir + QStringLiteral("/out"));
    run(QStringLiteral("nice"), {QStringLiteral("-n"), QStringLiteral("10"), QStringLiteral("makepkg"), QStringLiteral("-f"), QStringLiteral("--noconfirm")},
        [this, package, dir, env, retried](int code, const QString &out) {
            QFile log(dir + QStringLiteral("/build.log"));
            if (log.open(QIODevice::WriteOnly))
                log.write(out.toUtf8());
            if (code != 0) {
                // Подпись исходников ключом, которого у нас нет, — взять его.
                static const QRegularExpression unknownKey(QStringLiteral("unknown public key ([0-9A-Fa-f]{8,})"));
                const auto m = unknownKey.match(out);
                if (m.hasMatch() && !retried) {
                    Q_EMIT progress(-1, QStringLiteral("Беру ключ PGP автора"));
                    run(QStringLiteral("gpg"), {QStringLiteral("--recv-keys"), m.captured(1)}, [this, package](int, const QString &) {
                        makepkg(package, true);
                    });
                    return;
                }
                static const QRegularExpression error(QStringLiteral("==> ERROR: (.*)"));
                const auto e = error.match(out);
                fail(QStringLiteral("Сборка %1 не удалась: %2\nЖурнал: %3/build.log")
                         .arg(package.base, e.hasMatch() ? e.captured(1) : lastLines(out, 1), dir));
                return;
            }
            // Какие файлы получились: --packagelist — в порядке pkgname из .SRCINFO.
            run(QStringLiteral("makepkg"), {QStringLiteral("--packagelist")}, [this, package, dir](int, const QString &list) {
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
                // Ставим из разделённого пакета только то, что нужно.
                QStringList wanted;
                for (qsizetype i = 0; i < files.size() && i < names.size(); ++i) {
                    if (m_order.contains(names.at(i)) && QFile::exists(files.at(i)))
                        wanted << files.at(i);
                }
                if (wanted.isEmpty()) {
                    fail(QStringLiteral("После сборки %1 не нашлось пакета").arg(package.base));
                    return;
                }
                installBuilt(package, wanted);
            }, dir, env);
        },
        dir, env);
}

// ---- 4. Установка собранного

void AurBuild::installBuilt(const Package &package, const QStringList &files)
{
    const double share = 0.85 / qMax(1, int(m_order.size()));
    Q_EMIT progress(0.12 + m_index * share + share * 0.9, QStringLiteral("Устанавливаю %1").arg(package.name));
    // Зависимости — «как зависимости»: удалятся вместе с тем, кому нужны.
    const bool asDeps = !files.isEmpty() && !QFileInfo(files.constFirst()).fileName().startsWith(m_name + u'-');
    QStringList args{helper, QStringLiteral("install-files")};
    if (asDeps)
        args << QStringLiteral("--asdeps");
    args << files;
    run(QStringLiteral("pkexec"), args, [this](int code, const QString &out) {
        if (code == 126 || code == 127) {
            fail(QStringLiteral("Пароль не введён"), -1);
            return;
        }
        if (code != 0) {
            static const QRegularExpression error(QStringLiteral("ERROR (\\d+) (.*)"));
            const auto m = error.match(out);
            fail(m.hasMatch() ? m.captured(2) : lastLines(out, 2), m.hasMatch() ? m.captured(1).toInt() : 0);
            return;
        }
        // Все пакеты этого base уже поставлены — дальше.
        const QString base = m_aur.value(m_order.at(m_index)).base;
        while (m_index < m_order.size() && m_aur.value(m_order.at(m_index)).base == base)
            ++m_index;
        buildNext();
    });
}
