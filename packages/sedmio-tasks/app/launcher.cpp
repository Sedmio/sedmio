#include "launcher.h"

#include <KApplicationTrader>
#include <KService>
#include <KShell>

#include <QDir>
#include <QFileInfo>
#include <QProcess>
#include <QRandomGenerator>
#include <QStandardPaths>

namespace
{
// Как systemd-escape: буквы, цифры, «:_.» как есть, остальное — \xNN.
QString systemdEscape(const QString &text)
{
    QString out;
    const QByteArray bytes = text.toUtf8();
    for (int i = 0; i < bytes.size(); ++i) {
        const char c = bytes.at(i);
        const bool plain = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == ':' || c == '_'
            || (c == '.' && i > 0);
        if (plain)
            out += QLatin1Char(c);
        else
            out += QStringLiteral("\\x%1").arg(uchar(c), 2, 16, QLatin1Char('0'));
    }
    return out;
}

// Exec из .desktop без полей %f %U и прочих: файлов не передаём.
QStringList execArgs(const KService::Ptr &service)
{
    KShell::Errors error = KShell::NoError;
    const QStringList parts = KShell::splitArgs(service->exec(), KShell::NoOptions, &error);
    if (error != KShell::NoError)
        return {};
    QStringList argv;
    for (QString part : parts) {
        if (part == QLatin1String("%i")) {
            if (!service->icon().isEmpty())
                argv << QStringLiteral("--icon") << service->icon();
            continue;
        }
        if (part == QLatin1String("%c")) {
            argv << service->name();
            continue;
        }
        if (part == QLatin1String("%k")) {
            argv << service->entryPath();
            continue;
        }
        if (part.size() == 2 && part.startsWith(QLatin1Char('%')))
            continue;
        part.replace(QLatin1String("%%"), QLatin1String("%"));
        argv << part;
    }
    return argv;
}

bool matches(const KService::Ptr &service, const QString &query)
{
    const auto has = [&query](const QString &text) {
        return text.contains(query, Qt::CaseInsensitive);
    };
    if (has(service->name()) || has(service->genericName()) || has(service->untranslatedName()))
        return true;
    const QStringList keywords = service->keywords();
    for (const QString &keyword : keywords) {
        if (has(keyword))
            return true;
    }
    return QFileInfo(service->exec().section(QLatin1Char(' '), 0, 0)).fileName().startsWith(query, Qt::CaseInsensitive);
}
} // namespace

Launcher::Launcher(QObject *parent)
    : QObject(parent)
{
}

QVariantList Launcher::search(const QString &rawQuery) const
{
    const QString query = rawQuery.trimmed();
    if (query.isEmpty())
        return {};
    KService::List found = KApplicationTrader::query([&query](const KService::Ptr &service) {
        return !service->noDisplay() && !service->exec().isEmpty() && matches(service, query);
    });
    // Сначала те, чьё название начинается с запроса, потом по алфавиту.
    std::sort(found.begin(), found.end(), [&query](const KService::Ptr &a, const KService::Ptr &b) {
        const bool aStarts = a->name().startsWith(query, Qt::CaseInsensitive);
        const bool bStarts = b->name().startsWith(query, Qt::CaseInsensitive);
        if (aStarts != bStarts)
            return aStarts;
        return a->name().localeAwareCompare(b->name()) < 0;
    });
    QVariantList result;
    for (const KService::Ptr &service : std::as_const(found)) {
        if (result.size() >= 6)
            break;
        result << QVariantMap{
            {QStringLiteral("id"), service->storageId()},
            {QStringLiteral("name"), service->name()},
            {QStringLiteral("comment"), service->comment().isEmpty() ? service->genericName() : service->comment()},
            {QStringLiteral("icon"), service->icon().isEmpty() ? QStringLiteral("application-x-executable") : service->icon()},
        };
    }
    return result;
}

bool Launcher::launchApp(const QString &id)
{
    const KService::Ptr service = KService::serviceByStorageId(id);
    if (!service) {
        setError(QStringLiteral("Не найдено: %1").arg(id));
        return false;
    }
    const QStringList argv = execArgs(service);
    if (argv.isEmpty()) {
        setError(QStringLiteral("Не удалось запустить «%1»").arg(service->name()));
        return false;
    }
    QString desktopId = service->storageId();
    if (desktopId.endsWith(QLatin1String(".desktop")))
        desktopId.chop(8);
    return start(desktopId, argv, service->workingDirectory());
}

bool Launcher::runCommand(const QString &rawCommand)
{
    const QString command = rawCommand.trimmed();
    if (command.isEmpty())
        return false;
    KShell::Errors error = KShell::NoError;
    QStringList argv = KShell::splitArgs(command, KShell::TildeExpand | KShell::AbortOnMeta, &error);
    if (error == KShell::FoundMeta) {
        // Конвейеры, $ПЕРЕМЕННЫЕ и прочее — пусть разбирает sh.
        const QStringList first = KShell::splitArgs(command.section(QLatin1Char(' '), 0, 0), KShell::NoOptions);
        const QString id = first.isEmpty() ? QStringLiteral("sh") : QFileInfo(first.constFirst()).fileName();
        return start(id, {QStringLiteral("/bin/sh"), QStringLiteral("-c"), command});
    }
    if (error != KShell::NoError || argv.isEmpty()) {
        setError(QStringLiteral("Не понял команду: %1").arg(command));
        return false;
    }
    // Путь к папке или файлу — открыть его, как «Выполнить» в Windows.
    const QFileInfo info(argv.constFirst());
    if (argv.size() == 1 && info.isAbsolute() && info.exists() && !(info.isFile() && info.isExecutable()))
        return start(QStringLiteral("xdg-open"), {QStringLiteral("xdg-open"), argv.constFirst()});
    // Программа по названию («Firefox», «калькулятор») — первая подходящая.
    if (QStandardPaths::findExecutable(argv.constFirst()).isEmpty() && !info.isAbsolute()) {
        const QVariantList apps = search(command);
        if (!apps.isEmpty())
            return launchApp(apps.constFirst().toMap().value(QStringLiteral("id")).toString());
        setError(QStringLiteral("Не найдено: %1").arg(argv.constFirst()));
        return false;
    }
    return start(QFileInfo(argv.constFirst()).fileName(), argv);
}

bool Launcher::start(const QString &id, const QStringList &argv, const QString &workingDirectory)
{
    setError({});
    const QString directory = workingDirectory.isEmpty() ? QDir::homePath() : workingDirectory;
    // Своя группа app-<id>-<случайное>.scope в app.slice (соглашение XDG
    // для systemd): программа переживает диспетчер, а он видит её отдельно.
    const QString runtime = qEnvironmentVariable("XDG_RUNTIME_DIR");
    const QString systemdRun = QStandardPaths::findExecutable(QStringLiteral("systemd-run"));
    if (!runtime.isEmpty() && QFileInfo::exists(runtime + QStringLiteral("/systemd/private")) && !systemdRun.isEmpty()) {
        const QString unit = QStringLiteral("app-%1-%2").arg(systemdEscape(id)).arg(QRandomGenerator::global()->generate(), 8, 16, QLatin1Char('0'));
        QStringList args{QStringLiteral("--user"), QStringLiteral("--scope"), QStringLiteral("--quiet"), QStringLiteral("--collect"),
                         QStringLiteral("--slice=app.slice"), QStringLiteral("--unit=") + unit, QStringLiteral("--")};
        args << argv;
        if (QProcess::startDetached(systemdRun, args, directory))
            return true;
    }
    QStringList rest = argv;
    const QString program = rest.takeFirst();
    if (QProcess::startDetached(program, rest, directory))
        return true;
    setError(QStringLiteral("Не удалось запустить: %1").arg(program));
    return false;
}

void Launcher::setError(const QString &error)
{
    if (m_error == error)
        return;
    m_error = error;
    Q_EMIT errorChanged();
}
