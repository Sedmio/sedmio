#include "pkgscan.h"

#include <QDateTime>
#include <QHash>
#include <QRegularExpression>
#include <QSet>

namespace PkgScan
{
namespace
{
using Re = QRegularExpression;

struct Rule {
    QString level;
    Re pattern;
    QString message;
    bool pkgbuildOnly = false;
};

// Правила по строкам: PKGBUILD, скрипты установки (.install), скрипты
// пакета (*.sh, хуки pacman). Заплатки (*.patch) не смотрим — это код
// самой программы, а не сборки.
const QList<Rule> &lineRules()
{
    static const QList<Rule> rules = {
        // Так делают вредоносные пакеты.
        {QStringLiteral("danger"),
         Re(QStringLiteral(R"re(\b(curl|wget|fetch|aria2c)\b[^|#]*\|\s*(sudo\s+)?(ba|z|da|k|fi)?sh\b|\b(curl|wget)\b[^|#]*\|\s*(python3?|perl|ruby|node)\b)re")),
         QStringLiteral("Скачанное сразу выполняется — без проверки и без следа в пакете")},
        {QStringLiteral("danger"),
         Re(QStringLiteral(R"re((base64\s+(-d|--decode)|xxd\s+-r|openssl\s+(enc\s+)?-d|\bgunzip\b|\brev\b)[^#]*\|\s*(sudo\s+)?((ba|z)?sh|eval|source|python3?|perl)\b|\beval\b[^#]*(base64|xxd)|\bsource\s*<\(.*base64)re")),
         QStringLiteral("Закодированный текст расшифровывается и выполняется — так прячут вредный код")},
        {QStringLiteral("danger"),
         Re(QStringLiteral(R"re(/dev/(tcp|udp)/|\bn(c|cat|etcat)\b[^#]*\s-[a-z]*e\s|\bsocat\b[^#]*exec:|\bbash\s+-i\s*>&|\bmkfifo\b[^#]*\bn(c|cat)\b)re")),
         QStringLiteral("Похоже на «обратную оболочку» — доступ к компьютеру снаружи")},
        {QStringLiteral("danger"),
         Re(QStringLiteral(R"re(\.ssh/|\bid_(rsa|ed25519|ecdsa)\b|authorized_keys|\.gnupg/|\.mozilla/|\.config/(google-chrome|chromium|BraveSoftware|vivaldi|opera|discord)|Login Data|cookies\.sqlite|key4\.db|logins\.json|\.local/share/keyrings|wallet\.dat|\.electrum|\.config/Telegram)re")),
         QStringLiteral("Обращение к ключам SSH, паролям или данным браузера")},
        {QStringLiteral("danger"),
         Re(QStringLiteral(R"re(/etc/(sudoers|shadow|gshadow)\b|(>>?|\btee\b|sed\s+-i)[^#]*/etc/(passwd|group)\b)re")),
         QStringLiteral("Правка sudoers или учётных записей системы")},
        {QStringLiteral("danger"),
         Re(QStringLiteral(R"re(/etc/ld\.so\.preload|\bLD_PRELOAD=)re")),
         QStringLiteral("Подмешивание своей библиотеки во все программы (LD_PRELOAD)")},
        {QStringLiteral("danger"),
         Re(QStringLiteral(R"re(\brm\s+(-[a-zA-Z]*\s+)*-[a-zA-Z]*r[a-zA-Z]*\s+(-[a-zA-Z]*\s+)*("?(/|~|\$HOME|\$\{HOME\})"?/?\*?)(\s|;|$))re")),
         QStringLiteral("Удаление корня или домашней папки")},

        // Бывает и в честных пакетах — но стоит понять зачем.
        {QStringLiteral("check"), Re(QStringLiteral(R"re(\beval\b)re")),
         QStringLiteral("eval — выполняется текст, собранный на ходу: проверьте, откуда он")},
        {QStringLiteral("check"), Re(QStringLiteral(R"re(\bsudo\b)re")),
         QStringLiteral("sudo — пакет просит права root сам, мимо pacman")},
        {QStringLiteral("check"), Re(QStringLiteral(R"re(\b(curl|wget|aria2c)\b|\bgit\s+clone\b)re")),
         QStringLiteral("Загрузка мимо source=() — makepkg не проверит её контрольную сумму")},
        {QStringLiteral("check"), Re(QStringLiteral(R"re(base64\s+(-d|--decode)|\bxxd\s+-r)re")),
         QStringLiteral("Расшифровка закодированного текста — посмотрите, что в нём")},
        {QStringLiteral("check"),
         Re(QStringLiteral(R"re(\bchmod\s+(-[a-zA-Z]+\s+)*([ugoa]*\+[rwx]*s|[2467][0-7]{3})\b|\binstall\b[^#]*-[a-zA-Z]*m\s*[2467][0-7]{3}\b)re")),
         QStringLiteral("setuid/setgid — программа будет запускаться с правами владельца (часто root)")},
        {QStringLiteral("check"), Re(QStringLiteral(R"re(\bsystemctl\b[^#]*\b(enable|start|restart|mask|daemon-reload)\b)re")),
         QStringLiteral("Включает или запускает службу systemd")},
        {QStringLiteral("check"), Re(QStringLiteral(R"re(\bcrontab\b|(?<!pkgdir")(?<!pkgdir\})(?<!pkgdir)/etc/cron)re")),
         QStringLiteral("Задание по расписанию (cron)")},
        {QStringLiteral("check"), Re(QStringLiteral(R"re(\bchattr\s+[+-]i\b)re")),
         QStringLiteral("Файл делают неизменяемым (chattr +i) — его потом не удалить обычным путём")},
        {QStringLiteral("check"), Re(QStringLiteral(R"re(\b(useradd|usermod|groupadd|passwd)\b)re")),
         QStringLiteral("Заводит или меняет учётные записи")},
    };
    return rules;
}

bool isScript(const QString &name, const QString &text)
{
    if (name == QLatin1String("PKGBUILD"))
        return true;
    if (name.endsWith(QLatin1String(".install")) || name.endsWith(QLatin1String(".sh")) || name.endsWith(QLatin1String(".hook")))
        return true;
    return text.startsWith(QLatin1String("#!"));
}

// Строка без комментария в конце (# не в кавычках и не в ${#…}).
QString code(const QString &line)
{
    bool single = false, dbl = false;
    for (qsizetype i = 0; i < line.size(); ++i) {
        const QChar c = line.at(i);
        if (c == u'\\') {
            ++i;
            continue;
        }
        if (c == u'\'' && !dbl)
            single = !single;
        else if (c == u'"' && !single)
            dbl = !dbl;
        else if (c == u'#' && !single && !dbl && (i == 0 || line.at(i - 1).isSpace()))
            return line.left(i);
    }
    return line;
}

// Запись в систему мимо $pkgdir — в функциях PKGBUILD. При сборке makepkg
// работает от пользователя, так что «запись в /usr» значит: либо sudo,
// либо пакет потом окажется не тем.
bool writesOutsidePkgdir(const QString &line)
{
    static const Re root(QStringLiteral(R"re((^|[\s'"=])(/(usr|etc|opt|var|boot|root|srv|lib|lib64|bin|sbin)(/|\b|$)))re"));
    static const Re redirect(QStringLiteral(R"re(>>?\s*["']?/(usr|etc|opt|var|boot|root|srv|lib|bin|sbin)(/|\b))re"));
    static const Re anyArg(QStringLiteral(R"re(^\s*(sudo\s+)?(mkdir|touch|rm|chmod|chown|tee|truncate)\b)re"));
    static const Re destArg(QStringLiteral(R"re(^\s*(sudo\s+)?(install|cp|mv|ln|rsync)\b)re"));
    if (redirect.match(line).hasMatch())
        return true;
    const bool any = anyArg.match(line).hasMatch();
    const bool dest = destArg.match(line).hasMatch();
    if (!any && !dest)
        return false;
    // Последний аргумент (куда) или любой — для mkdir, rm…
    QStringList tokens = line.split(Re(QStringLiteral("\\s+")), Qt::SkipEmptyParts);
    if (dest && !tokens.isEmpty())
        tokens = {tokens.constLast()};
    for (QString t : std::as_const(tokens)) {
        t.remove(u'"').remove(u'\'');
        if (t.contains(u'$'))
            continue; // "$pkgdir"/usr, ${srcdir}/…
        if (root.match(t).hasMatch() && t.startsWith(u'/'))
            return true;
    }
    return false;
}

int distanceAtMostOne(const QString &a, const QString &b)
{
    if (a == b)
        return 0;
    const qsizetype la = a.size(), lb = b.size();
    if (qAbs(la - lb) > 1)
        return 2;
    qsizetype i = 0;
    while (i < la && i < lb && a.at(i) == b.at(i))
        ++i;
    if (la == lb)
        return a.mid(i + 1) == b.mid(i + 1) ? 1 : 2;
    return la > lb ? (a.mid(i + 1) == b.mid(i) ? 1 : 2) : (a.mid(i) == b.mid(i + 1) ? 1 : 2);
}

struct SrcInfo {
    // По архитектуре ("" и "_x86_64"): источники и суммы по видам.
    QHash<QString, QStringList> sources;
    QHash<QString, QHash<QString, QStringList>> sums;
};

SrcInfo parseSrcInfo(const QString &text)
{
    static const QStringList sumKinds{QStringLiteral("cksums"), QStringLiteral("md5sums"), QStringLiteral("sha1sums"), QStringLiteral("sha224sums"),
                                      QStringLiteral("sha256sums"), QStringLiteral("sha384sums"), QStringLiteral("sha512sums"), QStringLiteral("b2sums")};
    SrcInfo info;
    bool inBase = true;
    for (const QString &raw : text.split(u'\n')) {
        const QString line = raw.trimmed();
        if (line.startsWith(QLatin1String("pkgname =")))
            inBase = false; // дальше — разделённые пакеты, источники только у pkgbase
        if (!inBase)
            continue;
        const qsizetype eq = line.indexOf(QLatin1String(" = "));
        if (eq < 0)
            continue;
        const QString key = line.left(eq);
        const QString value = line.mid(eq + 3);
        for (const QString arch : {QString(), QStringLiteral("_x86_64")}) {
            if (key == QLatin1String("source") + arch)
                info.sources[arch] << value;
            for (const QString &kind : sumKinds) {
                if (key == kind + arch)
                    info.sums[arch][kind] << value;
            }
        }
    }
    return info;
}

QString sourceUrl(const QString &source)
{
    const qsizetype sep = source.indexOf(QLatin1String("::"));
    return sep >= 0 ? source.mid(sep + 2) : source;
}

bool isVcs(const QString &url)
{
    static const Re vcs(QStringLiteral(R"re(^(git|svn|hg|bzr|fossil)(\+|://))re"));
    return vcs.match(url).hasMatch();
}
} // namespace

QVariantMap toMap(const Finding &f)
{
    return {{QStringLiteral("level"), f.level},
            {QStringLiteral("file"), f.file},
            {QStringLiteral("line"), f.line},
            {QStringLiteral("message"), f.message}};
}

QList<QPair<QString, QString>> vcsSources(const QString &srcinfo)
{
    QList<QPair<QString, QString>> result;
    const SrcInfo info = parseSrcInfo(srcinfo);
    for (const QString arch : {QString(), QStringLiteral("_x86_64")}) {
        for (const QString &source : info.sources.value(arch)) {
            QString url = sourceUrl(source);
            if (!url.startsWith(QLatin1String("git+")) && !url.startsWith(QLatin1String("git://")))
                continue;
            if (url.startsWith(QLatin1String("git+")))
                url = url.mid(4);
            QString fragment;
            const qsizetype hash = url.indexOf(u'#');
            if (hash >= 0) {
                fragment = url.mid(hash + 1);
                url = url.left(hash);
            }
            const qsizetype query = url.indexOf(u'?');
            if (query >= 0)
                url = url.left(query);
            if (fragment.startsWith(QLatin1String("commit=")) || fragment.startsWith(QLatin1String("tag=")))
                continue; // закреплено — не «следит за веткой»
            const QString ref = fragment.startsWith(QLatin1String("branch=")) ? QStringLiteral("refs/heads/") + fragment.mid(7) : QStringLiteral("HEAD");
            result << qMakePair(url, ref);
        }
    }
    return result;
}

QList<Finding> scan(const QList<File> &files, const QString &srcinfo, const Record &record, const QStringList &repoNames)
{
    QList<Finding> findings;
    auto add = [&findings](const QString &level, const QString &file, int line, const QString &message) {
        findings << Finding{level, file, line, message};
    };

    // ---- Сведения AUR
    if (record.maintainer.isEmpty())
        add(QStringLiteral("check"), {}, 0, QStringLiteral("У пакета нет сопровождающего — его может забрать кто угодно"));
    if (!record.previousMaintainer.isEmpty() && !record.maintainer.isEmpty() && record.previousMaintainer != record.maintainer)
        add(QStringLiteral("check"), {}, 0,
            QStringLiteral("Сменился сопровождающий: был %1, теперь %2").arg(record.previousMaintainer, record.maintainer));
    if (record.firstSubmitted > 0) {
        const qint64 days = (QDateTime::currentSecsSinceEpoch() - record.firstSubmitted) / 86400;
        if (days < 14)
            add(QStringLiteral("check"), {}, 0,
                days < 1 ? QStringLiteral("Пакет появился в AUR сегодня") : QStringLiteral("Пакет появился в AUR %1 дн. назад").arg(days));
    }
    if (record.name.size() >= 5 && !repoNames.contains(record.name)) {
        for (const QString &repo : repoNames) {
            if (repo.size() >= 5 && distanceAtMostOne(record.name, repo) == 1) {
                add(QStringLiteral("check"), {}, 0,
                    QStringLiteral("Имя похоже на пакет из репозиториев «%1» — не подделка ли это под него?").arg(repo));
                break;
            }
        }
    }
    if (record.outOfDate)
        add(QStringLiteral("note"), {}, 0, QStringLiteral("Отмечен устаревшим — сборка может не получиться"));
    if (record.votes == 0)
        add(QStringLiteral("note"), {}, 0, QStringLiteral("За пакет ещё никто не голосовал"));

    // ---- Источники и суммы (.SRCINFO)
    const SrcInfo info = parseSrcInfo(srcinfo);
    // Слабые суммы — только если файл со стороны сверяется лишь md5/sha1
    // (SKIP у веток VCS — не в счёт).
    bool weakOnly = false;
    auto weakKind = [](const QString &kind) {
        return kind == QLatin1String("md5sums") || kind == QLatin1String("sha1sums") || kind == QLatin1String("cksums");
    };
    for (const QString arch : {QString(), QStringLiteral("_x86_64")}) {
        const QStringList sources = info.sources.value(arch);
        const auto sums = info.sums.value(arch);
        for (qsizetype i = 0; i < sources.size(); ++i) {
            const QString url = sourceUrl(sources.at(i));
            if (isVcs(url)) {
                if (!url.contains(QLatin1String("#commit=")) && !url.contains(QLatin1String("#tag=")))
                    add(QStringLiteral("note"), QStringLiteral(".SRCINFO"), 0,
                        QStringLiteral("Исходники из ветки VCS (%1): соберётся то, что там окажется в момент сборки").arg(url));
                continue;
            }
            if (!url.contains(QLatin1String("://")))
                continue; // файл из самого пакета — его вы видите здесь
            if (url.endsWith(QLatin1String(".sig")) || url.endsWith(QLatin1String(".asc")))
                continue;
            bool skipped = !sums.isEmpty();
            for (auto it = sums.cbegin(); it != sums.cend(); ++it) {
                if (it.value().value(i) != QLatin1String("SKIP"))
                    skipped = false;
            }
            if (sums.isEmpty() || skipped)
                add(QStringLiteral("check"), QStringLiteral(".SRCINFO"), 0,
                    QStringLiteral("Скачивается без контрольной суммы (SKIP): %1").arg(url));
            bool strong = false, weak = false;
            for (auto it = sums.cbegin(); it != sums.cend(); ++it) {
                const QString value = it.value().value(i);
                if (value.isEmpty() || value == QLatin1String("SKIP"))
                    continue;
                (weakKind(it.key()) ? weak : strong) = true;
            }
            weakOnly = weakOnly || (weak && !strong);
            if (url.startsWith(QLatin1String("http://")) || url.startsWith(QLatin1String("ftp://")))
                add(QStringLiteral("note"), QStringLiteral(".SRCINFO"), 0,
                    QStringLiteral("Скачивается без шифрования: %1").arg(url));
        }
    }
    if (weakOnly)
        add(QStringLiteral("note"), QStringLiteral(".SRCINFO"), 0,
            QStringLiteral("Устаревшие контрольные суммы (md5/sha1) — подделать файл под них проще"));

    // ---- Строки скриптов
    static const Re functionStart(QStringLiteral(R"re(^\s*(function\s+)?[A-Za-z_][A-Za-z0-9_-]*\s*\(\s*\)\s*\{?\s*$)re"));
    static const Re assignment(QStringLiteral(R"re(^\s*(export\s+|declare\s+(-\w+\s+)*|local\s+|readonly\s+)?[A-Za-z_][A-Za-z0-9_]*(\[[^\]]*\])?\+?=)re"));
    for (const File &file : files) {
        if (!isScript(file.name, file.text))
            continue;
        const bool pkgbuild = file.name == QLatin1String("PKGBUILD");
        const QStringList lines = file.text.split(u'\n');
        int depth = 0;     // вложенность { } — внутри функций
        int parens = 0;    // незакрытые ( в присваиваниях-массивах
        bool continued = false;
        bool inMeta = false; // внутри pkgdesc=, optdepends=(…) и т.п. — это текст, не команды
        QSet<QString> seen; // одно и то же сообщение в файле — не больше 3 раз
        QHash<QString, int> count;
        for (int n = 0; n < lines.size(); ++n) {
            const QString text = code(lines.at(n));
            const QString trimmed = text.trimmed();
            if (trimmed.isEmpty())
                continue;
            static const Re metaKey(QStringLiteral(
                R"re(^\s*(pkgdesc|url|license|(make|check|opt)?depends(_\w+)?|provides(_\w+)?|conflicts(_\w+)?|replaces(_\w+)?|source(_\w+)?|arch|groups|backup|options|validpgpkeys|\w*sums(_\w+)?|noextract|pkgname|pkgbase|pkgver|pkgrel|epoch|changelog|install)=)re"));
            const bool meta = pkgbuild && depth == 0 && (inMeta || metaKey.match(trimmed).hasMatch());
            // Сообщение человеку (echo "… usermod …") — не команда; опасные
            // правила всё равно смотрим: «echo … | base64 -d | sh».
            static const Re message(QStringLiteral(R"re(^\s*(echo|printf|msg2?|warning|plain|error)\b)re"));
            const bool talk = message.match(trimmed).hasMatch() && !trimmed.contains(u'|');
            for (const Rule &rule : lineRules()) {
                if (meta)
                    break;
                if (talk && rule.level != QLatin1String("danger"))
                    continue;
                if (rule.pkgbuildOnly && !pkgbuild)
                    continue;
                if (!rule.pattern.match(text).hasMatch())
                    continue;
                // Опасное уже сказано — то же место не повторяем мягче.
                if (seen.contains(QString::number(n)) && rule.level != QLatin1String("danger"))
                    continue;
                if (++count[rule.message] > 3)
                    continue;
                seen.insert(QString::number(n));
                add(rule.level, file.name, n + 1, rule.message);
            }
            if (pkgbuild && depth > 0 && writesOutsidePkgdir(text) && !seen.contains(QString::number(n)) && ++count[QStringLiteral("write")] <= 3)
                add(QStringLiteral("check"), file.name, n + 1, QStringLiteral("Запись в систему мимо $pkgdir — при сборке так не делают"));

            // Команды вне функций в PKGBUILD выполняются при каждом его чтении.
            if (pkgbuild) {
                const bool wasTop = depth == 0 && parens == 0 && !continued;
                if (wasTop && !functionStart.match(trimmed).hasMatch() && !assignment.match(trimmed).hasMatch()
                    && trimmed != QLatin1String("}") && trimmed != QLatin1String("{") && trimmed != QLatin1String(")")
                    && ++count[QStringLiteral("top")] <= 3)
                    add(QStringLiteral("note"), file.name, n + 1,
                        QStringLiteral("Команда вне функций — выполняется при любом чтении PKGBUILD, ещё до сборки"));
                for (const QChar c : text) {
                    if (c == u'{')
                        ++depth;
                    else if (c == u'}')
                        depth = qMax(0, depth - 1);
                    else if (c == u'(')
                        ++parens;
                    else if (c == u')')
                        parens = qMax(0, parens - 1);
                }
                continued = trimmed.endsWith(u'\\');
                inMeta = meta && parens > 0;
            }
        }
    }

    // Опасное — первым.
    auto rank = [](const QString &level) {
        return level == QLatin1String("danger") ? 0 : level == QLatin1String("check") ? 1 : 2;
    };
    std::stable_sort(findings.begin(), findings.end(), [&rank](const Finding &a, const Finding &b) {
        return rank(a.level) < rank(b.level);
    });
    return findings;
}
} // namespace PkgScan
