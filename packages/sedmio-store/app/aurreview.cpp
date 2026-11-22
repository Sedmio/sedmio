#include "aurreview.h"
#include "aur.h"
#include "catalog.h"

#include <QCryptographicHash>
#include <QDateTime>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QStringDecoder>
#include <QTimer>

namespace
{
const int maxPackages = 30;
const qint64 maxText = 1024 * 1024;

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

// PKGBUILD — первым, потом скрипты установки, потом остальное по имени.
int fileRank(const QString &name)
{
    if (name == QLatin1String("PKGBUILD"))
        return 0;
    if (name.endsWith(QLatin1String(".install")))
        return 1;
    if (name.endsWith(QLatin1String(".sh")) || name.endsWith(QLatin1String(".hook")))
        return 2;
    if (name == QLatin1String(".SRCINFO"))
        return 9;
    return 3;
}
} // namespace

AurReview::AurReview(QObject *parent)
    : QObject(parent)
{
}

QString AurReview::reviewDir(const QString &base)
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericCacheLocation) + QStringLiteral("/sedmio-store/aur/review/") + base;
}

QByteArray AurReview::treeHash(const QString &dir)
{
    QStringList files;
    QDirIterator it(dir, QDir::Files | QDir::Hidden | QDir::NoSymLinks, QDirIterator::Subdirectories);
    while (it.hasNext())
        files << QDir(dir).relativeFilePath(it.next());
    files.sort();
    QCryptographicHash hash(QCryptographicHash::Sha256);
    for (const QString &name : std::as_const(files)) {
        QFile file(dir + u'/' + name);
        if (!file.open(QIODevice::ReadOnly))
            return {};
        hash.addData(name.toUtf8());
        hash.addData(QByteArrayView("\0", 1));
        hash.addData(&file);
        hash.addData(QByteArrayView("\0", 1));
    }
    // Ссылки тоже считаются: подменить файл ссылкой — тоже изменение.
    QDirIterator links(dir, QDir::System | QDir::Files | QDir::Dirs | QDir::Hidden | QDir::NoDotAndDotDot, QDirIterator::Subdirectories);
    while (links.hasNext()) {
        const QFileInfo info(links.next());
        if (info.isSymLink())
            hash.addData((QStringLiteral("link:") + QDir(dir).relativeFilePath(info.filePath()) + u'>' + info.symLinkTarget()).toUtf8());
    }
    return hash.result().toHex();
}

void AurReview::run(const QString &program, const QStringList &args, std::function<void(int, const QString &)> done, const QString &workdir,
                    bool cLocale)
{
    auto *process = new QProcess(this);
    process->setProcessChannelMode(QProcess::MergedChannels);
    QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
    if (cLocale)
        env.insert(QStringLiteral("LC_ALL"), QStringLiteral("C"));
    env.insert(QStringLiteral("GIT_TERMINAL_PROMPT"), QStringLiteral("0"));
    process->setProcessEnvironment(env);
    if (!workdir.isEmpty())
        process->setWorkingDirectory(workdir);
    const int generation = m_generation;
    // Зависший сервер git не должен держать просмотр вечно.
    QTimer::singleShot(30000, process, [process] { process->kill(); });
    connect(process, &QProcess::finished, this, [this, process, done, generation](int code, QProcess::ExitStatus status) {
        process->deleteLater();
        if (generation != m_generation)
            return;
        done(status == QProcess::NormalExit ? code : -2, QString::fromUtf8(process->readAll()));
    });
    connect(process, &QProcess::errorOccurred, this, [this, process, program, done, generation](QProcess::ProcessError error) {
        if (error != QProcess::FailedToStart)
            return;
        process->deleteLater();
        if (generation == m_generation)
            done(-3, QStringLiteral("не запускается ") + program);
    });
    process->start(program, args);
}

void AurReview::setStatus(const QString &status)
{
    m_status = status;
    Q_EMIT changed();
}

void AurReview::fail(const QString &error)
{
    m_state = QStringLiteral("failed");
    m_error = error;
    Q_EMIT changed();
}

void AurReview::start(const QStringList &targets)
{
    ++m_generation;
    m_targets = targets;
    m_aur.clear();
    m_depends.clear();
    m_pending.clear();
    m_seen.clear();
    m_repoDeps.clear();
    m_repoDownload = 0;
    m_order.clear();
    m_bases.clear();
    m_fetchIndex = 0;
    m_error.clear();
    m_state = QStringLiteral("loading");
    if (targets.isEmpty()) {
        fail(QStringLiteral("Нечего собирать"));
        return;
    }
    for (const QString &t : targets)
        m_seen.insert(t);
    setStatus(QStringLiteral("Смотрю зависимости"));
    resolve(targets);
}

// ---- 1. Что нужно

void AurReview::resolve(const QStringList &names)
{
    m_pending << names;
    const int generation = m_generation;
    Aur::instance()->infoMany(names, [this, names, generation](const QList<QVariantMap> &list, const QString &error) {
        if (generation != m_generation)
            return;
        if (!error.isEmpty()) {
            fail(error);
            return;
        }
        QStringList deps;
        QSet<QString> found;
        for (const QVariantMap &info : list) {
            const QString name = info.value(QStringLiteral("name")).toString();
            QStringList depends;
            for (const QString &dep : info.value(QStringLiteral("depends")).toStringList() + info.value(QStringLiteral("makeDepends")).toStringList()) {
                const QString bare = bareName(dep);
                if (!bare.isEmpty() && !depends.contains(bare))
                    depends << bare;
            }
            m_aur.insert(name, info);
            m_depends.insert(name, depends);
            found.insert(name);
            for (const QString &dep : std::as_const(depends)) {
                if (!m_seen.contains(dep)) {
                    m_seen.insert(dep);
                    deps << dep;
                }
            }
        }
        for (const QString &name : names) {
            if (!found.contains(name)) {
                fail(m_targets.contains(name) ? QStringLiteral("Пакета %1 нет в AUR").arg(name)
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
        if (deps.isEmpty()) {
            if (m_pending.isEmpty())
                resolved();
            return;
        }
        // Что из зависимостей уже стоит (с учётом provides) — pacman -T.
        run(QStringLiteral("pacman"), QStringList{QStringLiteral("-T"), QStringLiteral("--")} + deps, [this](int, const QString &out) {
            classify(out.split(u'\n', Qt::SkipEmptyParts));
        });
    });
}

void AurReview::classify(const QStringList &missing)
{
    if (missing.isEmpty()) {
        if (m_pending.isEmpty())
            resolved();
        return;
    }
    // Чего нет в репозиториях (pacman -Sp найдёт и «provides») — ищем в AUR.
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
            resolved();
    }, {}, true);
}

void AurReview::resolved()
{
    // Порядок: зависимости — раньше тех, кому нужны.
    QSet<QString> visited;
    std::function<void(const QString &)> visit = [&](const QString &name) {
        if (visited.contains(name) || !m_aur.contains(name))
            return;
        visited.insert(name);
        for (const QString &dep : m_depends.value(name))
            visit(dep);
        m_order << name;
    };
    for (const QString &t : std::as_const(m_targets))
        visit(t);
    // По base: разделённый пакет собирается один раз.
    for (const QString &name : std::as_const(m_order)) {
        const QVariantMap info = m_aur.value(name);
        const QString base = info.value(QStringLiteral("base")).toString();
        auto it = std::find_if(m_bases.begin(), m_bases.end(), [&base](const Base &b) { return b.base == base; });
        if (it == m_bases.end()) {
            Base b;
            b.base = base;
            b.info = info;
            m_bases << b;
            it = m_bases.end() - 1;
        }
        it->names << name;
        if (m_targets.contains(name))
            it->target = true;
    }
    m_fetchIndex = 0;
    fetchNext();
}

// ---- 2. Скачать и посмотреть каждый

void AurReview::fetchNext()
{
    if (m_fetchIndex >= m_bases.size()) {
        finishPlan();
        return;
    }
    const QString base = m_bases.at(m_fetchIndex).base;
    setStatus(QStringLiteral("Скачиваю %1 (%2 из %3)").arg(base).arg(m_fetchIndex + 1).arg(m_bases.size()));
    const QString dir = reviewDir(base);
    QDir(dir).removeRecursively();
    QDir().mkpath(QFileInfo(dir).path());
    const int generation = m_generation;
    Aur::instance()->fetch(QStringLiteral("https://aur.archlinux.org/cgit/aur.git/snapshot/%1.tar.gz").arg(base),
                           [this, base, dir, generation](const QByteArray &data, const QString &error) {
        if (generation != m_generation)
            return;
        if (!error.isEmpty()) {
            fail(QStringLiteral("%1: %2").arg(base, error));
            return;
        }
        const QString archive = dir + QStringLiteral(".tar.gz");
        QFile file(archive);
        if (!file.open(QIODevice::WriteOnly) || file.write(data) < 0) {
            fail(QStringLiteral("Не записать %1").arg(archive));
            return;
        }
        file.close();
        // В архиве — папка <base>/. Ссылки наружу и «../» bsdtar не пустит.
        run(QStringLiteral("bsdtar"), {QStringLiteral("-xf"), archive, QStringLiteral("-C"), QFileInfo(dir).path()},
            [this, base, archive, dir](int code, const QString &out) {
                QFile::remove(archive);
                if (code != 0 || !QFile::exists(dir + QStringLiteral("/PKGBUILD"))) {
                    fail(QStringLiteral("Архив %1 не распаковался: %2").arg(base, lastLines(out, 1)));
                    return;
                }
                inspect(m_bases[m_fetchIndex]);
            });
    });
}

void AurReview::inspect(Base &b)
{
    const QString dir = reviewDir(b.base);
    b.hash = treeHash(dir);
    QDirIterator it(dir, QDir::Files | QDir::Hidden | QDir::NoSymLinks, QDirIterator::Subdirectories);
    QString srcinfo;
    while (it.hasNext()) {
        const QString path = it.next();
        const QString name = QDir(dir).relativeFilePath(path);
        QFile file(path);
        b.sizes.insert(name, file.size());
        if (!file.open(QIODevice::ReadOnly))
            continue;
        const QByteArray head = file.peek(8192);
        // Не текст — нулевые байты или не UTF-8 (обрезанный в конце символ
        // декодер ошибкой не считает).
        QStringDecoder utf8(QStringDecoder::Utf8);
        (void)utf8.decode(head);
        if (head.contains('\0') || utf8.hasError()) {
            b.binary << name;
            continue;
        }
        const QString text = QString::fromUtf8(file.read(maxText));
        if (name == QLatin1String(".SRCINFO"))
            srcinfo = text;
        b.files << PkgScan::File{name, text};
    }
    std::sort(b.files.begin(), b.files.end(), [](const PkgScan::File &x, const PkgScan::File &y) {
        const int rx = fileRank(x.name), ry = fileRank(y.name);
        return rx != ry ? rx < ry : x.name < y.name;
    });

    PkgScan::Record record;
    record.name = b.names.value(0);
    record.maintainer = b.info.value(QStringLiteral("maintainer")).toString();
    record.previousMaintainer = Aur::instance()->rememberedMaintainer(record.name);
    record.firstSubmitted = b.info.value(QStringLiteral("firstSubmitted")).toLongLong();
    record.outOfDate = b.info.value(QStringLiteral("outOfDate")).toBool();
    record.votes = b.info.value(QStringLiteral("votes")).toInt();
    const Catalog *catalog = Catalog::instance();
    const QStringList repoNames = catalog ? catalog->packages().sync().keys() : QStringList();
    b.findings = PkgScan::scan(b.files, srcinfo, record, repoNames);

    // Какие коммиты сейчас в ветках VCS — запомним при установке, чтобы
    // потом заметить новые (у пакетов -git версия в AUR не меняется).
    const auto sources = PkgScan::vcsSources(srcinfo);
    if (sources.isEmpty() || QStandardPaths::findExecutable(QStringLiteral("git")).isEmpty()) {
        ++m_fetchIndex;
        fetchNext();
        return;
    }
    auto left = std::make_shared<int>(int(sources.size()));
    const int index = m_fetchIndex;
    for (const auto &source : sources) {
        run(QStringLiteral("git"), {QStringLiteral("ls-remote"), QStringLiteral("--"), source.first, source.second},
            [this, source, left, index](int code, const QString &out) {
                if (code == 0) {
                    const QString commit = out.section(u'\t', 0, 0).trimmed();
                    if (!commit.isEmpty())
                        m_bases[index].vcs.insert(source.first + u' ' + source.second, commit);
                }
                if (--*left == 0) {
                    ++m_fetchIndex;
                    fetchNext();
                }
            });
    }
}

// ---- 3. Что поставится из репозиториев

void AurReview::finishPlan()
{
    QStringList deps = m_repoDeps;
    const QString baseDevel = QStringLiteral("base-devel");
    run(QStringLiteral("pacman"), {QStringLiteral("-T"), baseDevel}, [this, deps, baseDevel](int, const QString &out) mutable {
        if (!out.trimmed().isEmpty() && !deps.contains(baseDevel))
            deps.prepend(baseDevel);
        m_repoDeps = deps;
        if (deps.isEmpty()) {
            m_state = QStringLiteral("ready");
            m_status.clear();
            Q_EMIT changed();
            return;
        }
        // Размер скачивания: pacman -Sp печатает и зависимости зависимостей.
        run(QStringLiteral("pacman"), QStringList{QStringLiteral("-Sp"), QStringLiteral("--print-format"), QStringLiteral("%s"), QStringLiteral("--")} + deps,
            [this](int, const QString &sizes) {
                qint64 total = 0;
                for (const QString &line : sizes.split(u'\n', Qt::SkipEmptyParts))
                    total += line.trimmed().toLongLong();
                m_repoDownload = total;
                m_state = QStringLiteral("ready");
                m_status.clear();
                Q_EMIT changed();
            }, {}, true);
    });
}

// ---- Для страницы

QVariantList AurReview::packages() const
{
    QVariantList list;
    const Catalog *catalog = Catalog::instance();
    for (const Base &b : m_bases) {
        QVariantList files;
        for (const PkgScan::File &f : b.files)
            files << QVariantMap{{QStringLiteral("name"), f.name}, {QStringLiteral("binary"), false}, {QStringLiteral("size"), b.sizes.value(f.name)}};
        for (const QString &name : b.binary)
            files << QVariantMap{{QStringLiteral("name"), name}, {QStringLiteral("binary"), true}, {QStringLiteral("size"), b.sizes.value(name)}};
        QVariantList findings;
        int danger = 0, check = 0, note = 0;
        for (const PkgScan::Finding &f : b.findings) {
            findings << PkgScan::toMap(f);
            if (f.level == QLatin1String("danger"))
                ++danger;
            else if (f.level == QLatin1String("check"))
                ++check;
            else
                ++note;
        }
        const qint64 submitted = b.info.value(QStringLiteral("firstSubmitted")).toLongLong();
        list << QVariantMap{
            {QStringLiteral("base"), b.base},
            {QStringLiteral("names"), b.names},
            {QStringLiteral("version"), b.info.value(QStringLiteral("version"))},
            {QStringLiteral("installed"), catalog ? catalog->packages().installed().value(b.names.value(0)) : QString()},
            {QStringLiteral("summary"), b.info.value(QStringLiteral("summary"))},
            {QStringLiteral("maintainer"), b.info.value(QStringLiteral("maintainer"))},
            {QStringLiteral("votes"), b.info.value(QStringLiteral("votes"))},
            {QStringLiteral("submitted"), submitted > 0 ? QDateTime::fromSecsSinceEpoch(submitted).date().toString(QStringLiteral("dd.MM.yyyy")) : QString()},
            {QStringLiteral("updated"), b.info.value(QStringLiteral("updated"))},
            {QStringLiteral("url"), b.info.value(QStringLiteral("url"))},
            {QStringLiteral("target"), b.target},
            {QStringLiteral("files"), files},
            {QStringLiteral("findings"), findings},
            {QStringLiteral("danger"), danger},
            {QStringLiteral("check"), check},
            {QStringLiteral("note"), note},
            {QStringLiteral("reviewed"), b.reviewed},
        };
    }
    return list;
}

bool AurReview::allReviewed() const
{
    return m_state == QLatin1String("ready") && !m_bases.isEmpty()
        && std::all_of(m_bases.cbegin(), m_bases.cend(), [](const Base &b) { return b.reviewed; });
}

QString AurReview::fileText(const QString &base, const QString &file) const
{
    for (const Base &b : m_bases) {
        if (b.base != base)
            continue;
        for (const PkgScan::File &f : b.files) {
            if (f.name == file)
                return f.text;
        }
    }
    return {};
}

void AurReview::setReviewed(const QString &base, bool reviewed)
{
    for (Base &b : m_bases) {
        if (b.base == base)
            b.reviewed = reviewed;
    }
    Q_EMIT changed();
}

QVariantMap AurReview::plan() const
{
    if (!allReviewed())
        return {};
    QVariantList order;
    QVariantMap bases;
    for (const Base &b : m_bases) {
        for (const QString &name : b.names)
            order << QVariantMap{{QStringLiteral("name"), name}, {QStringLiteral("base"), b.base}};
        QVariantMap vcs;
        for (auto it = b.vcs.cbegin(); it != b.vcs.cend(); ++it)
            vcs.insert(it.key(), it.value());
        bases.insert(b.base, QVariantMap{{QStringLiteral("dir"), reviewDir(b.base)},
                                         {QStringLiteral("hash"), QString::fromLatin1(b.hash)},
                                         {QStringLiteral("maintainer"), b.info.value(QStringLiteral("maintainer"))},
                                         {QStringLiteral("vcs"), vcs}});
    }
    return {{QStringLiteral("targets"), m_targets},
            {QStringLiteral("order"), order},
            {QStringLiteral("repoDeps"), m_repoDeps},
            {QStringLiteral("bases"), bases}};
}
