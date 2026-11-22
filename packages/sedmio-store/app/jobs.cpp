#include "jobs.h"
#include "aurbuild.h"
#include "flatpakops.h"

#include <QCoreApplication>
#include <QThread>
#include <QTimer>

#include <gio/gio.h>

namespace
{
const QString helper = QStringLiteral("/usr/lib/sedmio/store-helper");

QVariantMap sourceOf(const QVariantMap &app, const QString &kind)
{
    for (const QVariant &v : app.value(QStringLiteral("sources")).toList()) {
        const QVariantMap source = v.toMap();
        if (source.value(QStringLiteral("kind")).toString() == kind)
            return source;
    }
    return {};
}
} // namespace

Jobs::Jobs(QObject *parent)
    : QObject(parent)
{
}

Jobs *Jobs::instance()
{
    static Jobs *jobs = new Jobs;
    QJSEngine::setObjectOwnership(jobs, QJSEngine::CppOwnership);
    return jobs;
}

QVariantList Jobs::list() const
{
    QVariantList result;
    for (const Job &job : m_jobs)
        result << toMap(job);
    return result;
}

bool Jobs::busy() const
{
    return std::any_of(m_jobs.cbegin(), m_jobs.cend(), [](const Job &job) {
        return job.state == QLatin1String("waiting") || job.state == QLatin1String("running");
    });
}

QVariantMap Jobs::toMap(const Job &job) const
{
    return {
        {QStringLiteral("id"), job.id},
        {QStringLiteral("appId"), job.appId},
        {QStringLiteral("name"), job.name},
        {QStringLiteral("icon"), job.icon},
        {QStringLiteral("kind"), job.kind},
        {QStringLiteral("action"), job.action},
        {QStringLiteral("state"), job.state},
        {QStringLiteral("progress"), job.progress},
        {QStringLiteral("text"), job.text},
        {QStringLiteral("error"), job.error},
        {QStringLiteral("code"), job.code},
        // Pacman, пока идёт, не прерываем: оборванная установка хуже любой.
        {QStringLiteral("cancellable"), job.state == QLatin1String("waiting") || (job.state == QLatin1String("running") && (job.kind == QLatin1String("flathub") || (job.kind == QLatin1String("aur") && job.action != QLatin1String("remove"))))},
    };
}

Jobs::Job *Jobs::find(int id)
{
    for (Job &job : m_jobs) {
        if (job.id == id)
            return &job;
    }
    return nullptr;
}

void Jobs::install(const QVariantMap &app, const QString &kind)
{
    const QVariantMap source = sourceOf(app, kind);
    if (source.isEmpty())
        return;
    Job job;
    job.appId = app.value(QStringLiteral("id")).toString();
    job.name = app.value(QStringLiteral("name")).toString();
    job.icon = app.value(QStringLiteral("icon")).toString();
    job.kind = kind;
    job.action = QStringLiteral("install");
    if (kind == QLatin1String("arch")) {
        job.targets = {source.value(QStringLiteral("package")).toString()};
    } else {
        job.targets = {source.value(QStringLiteral("ref")).toString()};
        job.origin = source.value(QStringLiteral("origin")).toString();
    }
    enqueue(job);
}

void Jobs::remove(const QVariantMap &app, const QString &kind, bool deleteData)
{
    const QVariantMap source = sourceOf(app, kind);
    if (source.isEmpty())
        return;
    Job job;
    job.appId = app.value(QStringLiteral("id")).toString();
    job.name = app.value(QStringLiteral("name")).toString();
    job.icon = app.value(QStringLiteral("icon")).toString();
    job.kind = kind;
    job.action = QStringLiteral("remove");
    job.deleteData = deleteData;
    if (kind == QLatin1String("arch")) {
        job.targets = {source.value(QStringLiteral("package")).toString()};
    } else {
        job.targets = {source.value(QStringLiteral("ref")).toString()};
        job.user = source.value(QStringLiteral("userInstall"), true).toBool();
    }
    enqueue(job);
}

void Jobs::buildAur(const QVariantMap &plan, const QString &action)
{
    const QStringList targets = plan.value(QStringLiteral("targets")).toStringList();
    if (targets.isEmpty())
        return;
    Job job;
    job.appId = targets.size() == 1 ? QStringLiteral("aur:") + targets.constFirst() : QStringLiteral("aur:@updates");
    job.name = targets.size() == 1 ? targets.constFirst() : QStringLiteral("Обновления AUR");
    job.kind = QStringLiteral("aur");
    job.action = action == QLatin1String("update") ? QStringLiteral("update") : QStringLiteral("install");
    job.targets = targets;
    job.plan = plan;
    enqueue(job);
}

QString Jobs::log(int id) const
{
    for (const Job &job : m_jobs) {
        if (job.id == id)
            return job.log;
    }
    return {};
}

void Jobs::appendLog(int id, const QString &text)
{
    Job *job = find(id);
    if (!job)
        return;
    job->log += text;
    if (job->log.size() > 300000)
        job->log = job->log.right(250000);
    // Не чаще пяти раз в секунду: makepkg пишет быстро.
    if (m_logPending)
        return;
    m_logPending = true;
    QTimer::singleShot(200, this, [this] {
        m_logPending = false;
        ++m_logRevision;
        Q_EMIT logChanged();
    });
}

void Jobs::removeAur(const QString &name)
{
    Job job;
    job.appId = QStringLiteral("aur:") + name;
    job.name = name;
    job.kind = QStringLiteral("aur");
    job.action = QStringLiteral("remove");
    job.targets = {name};
    enqueue(job);
}

void Jobs::updateFlatpaks(const QVariantList &apps)
{
    Job job;
    job.kind = QStringLiteral("flathub");
    job.action = QStringLiteral("update");
    for (const QVariant &v : apps)
        job.targets << v.toMap().value(QStringLiteral("ref")).toString();
    if (apps.size() == 1) {
        const QVariantMap app = apps.constFirst().toMap();
        job.appId = app.value(QStringLiteral("id")).toString();
        job.name = app.value(QStringLiteral("name")).toString();
        job.icon = app.value(QStringLiteral("icon")).toString();
    } else {
        job.appId = QStringLiteral("@updates");
        job.name = QStringLiteral("Обновления Flathub");
    }
    enqueue(job);
}

void Jobs::enqueue(Job job)
{
    // То же самое уже ждёт или идёт — второй раз не ставим.
    for (const Job &other : std::as_const(m_jobs)) {
        if (other.appId == job.appId && other.kind == job.kind && other.action == job.action
            && (other.state == QLatin1String("waiting") || other.state == QLatin1String("running")))
            return;
    }
    // Прежний итог той же программы больше не нужен.
    m_jobs.removeIf([&job](const Job &other) {
        return other.appId == job.appId && other.state != QLatin1String("waiting") && other.state != QLatin1String("running");
    });
    job.id = m_nextId++;
    job.text = QStringLiteral("В очереди");
    m_jobs << job;
    Q_EMIT changed();
    next();
}

QVariantMap Jobs::forApp(const QString &appId) const
{
    for (auto it = m_jobs.crbegin(); it != m_jobs.crend(); ++it) {
        if (it->appId == appId)
            return toMap(*it);
    }
    return {};
}

void Jobs::cancel(int id)
{
    Job *job = find(id);
    if (!job)
        return;
    if (job->state == QLatin1String("waiting")) {
        job->state = QStringLiteral("cancelled");
        job->text = QStringLiteral("Отменено");
        Q_EMIT changed();
        return;
    }
    if (job->state == QLatin1String("running") && job->cancellable)
        g_cancellable_cancel(job->cancellable);
    if (job->state == QLatin1String("running") && job->build)
        static_cast<AurBuild *>(job->build.data())->cancel();
}

void Jobs::dismiss(int id)
{
    m_jobs.removeIf([id](const Job &job) {
        return job.id == id && job.state != QLatin1String("waiting") && job.state != QLatin1String("running");
    });
    Q_EMIT changed();
}

void Jobs::next()
{
    for (const Job &job : std::as_const(m_jobs)) {
        if (job.state == QLatin1String("running"))
            return;
    }
    for (Job &job : m_jobs) {
        if (job.state != QLatin1String("waiting"))
            continue;
        job.state = QStringLiteral("running");
        job.progress = -1;
        if (job.kind == QLatin1String("arch") || (job.kind == QLatin1String("aur") && job.action == QLatin1String("remove")))
            runPacman(job);
        else if (job.kind == QLatin1String("aur"))
            runAur(job);
        else
            runFlatpak(job);
        Q_EMIT changed();
        return;
    }
}

void Jobs::runPacman(Job &job)
{
    job.text = QStringLiteral("Ждёт пароля");
    auto *process = new QProcess(this);
    job.process = process;
    const int id = job.id;
    auto pending = std::make_shared<QByteArray>();
    auto error = std::make_shared<std::pair<int, QString>>(0, QString());
    connect(process, &QProcess::readyReadStandardOutput, this, [this, process, id, pending, error] {
        *pending += process->readAllStandardOutput();
        qsizetype end;
        while ((end = pending->indexOf('\n')) >= 0) {
            const QString line = QString::fromUtf8(pending->left(end));
            pending->remove(0, end + 1);
            Job *job = find(id);
            if (!job)
                continue;
            if (line.startsWith(QLatin1String("STEP "))) {
                job->text = line.mid(5);
            } else if (line.startsWith(QLatin1String("PROGRESS "))) {
                const QStringList parts = line.split(u' ');
                const double n = parts.value(1).toDouble();
                const double total = parts.value(2).toDouble();
                if (total > 0)
                    job->progress = qBound(0.0, (n - 0.5) / total, 1.0);
            } else if (line.startsWith(QLatin1String("LOG "))) {
                appendLog(id, line.mid(4) + u'\n');
                continue;
            } else if (line.startsWith(QLatin1String("ERROR "))) {
                error->first = line.section(u' ', 1, 1).toInt();
                error->second = line.section(u' ', 2);
            }
            Q_EMIT changed();
        }
    });
    connect(process, &QProcess::finished, this, [this, process, id, error](int code, QProcess::ExitStatus status) {
        process->deleteLater();
        if (status == QProcess::NormalExit && code == 0) {
            finish(id, {});
            return;
        }
        if (!error->second.isEmpty()) {
            finish(id, error->second, error->first);
            return;
        }
        // pkexec: 126 — окно пароля закрыли, 127 — не разрешено.
        if (code == 126 || code == 127) {
            finish(id, QStringLiteral("Пароль не введён"), -1);
            return;
        }
        const QString err = QString::fromUtf8(process->readAllStandardError()).trimmed();
        finish(id, err.isEmpty() ? QStringLiteral("Не получилось (код %1)").arg(code) : err);
    });
    QStringList args{helper, job.action == QLatin1String("remove") ? QStringLiteral("remove") : QStringLiteral("install")};
    args << job.targets;
    process->start(QStringLiteral("pkexec"), args);
}

void Jobs::runFlatpak(Job &job)
{
    job.text = job.action == QLatin1String("remove") ? QStringLiteral("Удаляю") : QStringLiteral("Готовлю");
    job.cancellable = g_cancellable_new();
    const int id = job.id;
    const Job copy = job;
    QPointer<Jobs> self(this);
    FlatpakOps::Progress progress = [self, id](double fraction, const QString &text) {
        QMetaObject::invokeMethod(QCoreApplication::instance(), [self, id, fraction, text] {
            if (!self)
                return;
            Job *job = self->find(id);
            if (!job || job->state != QLatin1String("running"))
                return;
            job->progress = fraction;
            job->text = text;
            Q_EMIT self->changed();
        });
    };
    QThread *thread = QThread::create([self, id, copy, progress] {
        QString error;
        if (copy.action == QLatin1String("install"))
            error = FlatpakOps::install(copy.origin, copy.targets.value(0), progress, copy.cancellable);
        else if (copy.action == QLatin1String("remove"))
            error = FlatpakOps::uninstall(copy.targets.value(0), copy.user, copy.deleteData, progress, copy.cancellable);
        else
            error = FlatpakOps::update(copy.targets, progress, copy.cancellable);
        QMetaObject::invokeMethod(QCoreApplication::instance(), [self, id, error] {
            if (self)
                self->finish(id, error);
        });
    });
    connect(thread, &QThread::finished, thread, &QObject::deleteLater);
    thread->start();
}

void Jobs::runAur(Job &job)
{
    job.text = QStringLiteral("Готовлю");
    auto *build = new AurBuild(job.plan, this);
    job.build = build;
    const int id = job.id;
    connect(build, &AurBuild::progress, this, [this, id](double fraction, const QString &text) {
        Job *job = find(id);
        if (!job || job->state != QLatin1String("running"))
            return;
        if (fraction >= 0)
            job->progress = fraction;
        job->text = text;
        Q_EMIT changed();
    });
    connect(build, &AurBuild::output, this, [this, id](const QString &text) { appendLog(id, text); });
    connect(build, &AurBuild::finished, this, [this, id, build](const QString &error, int code) {
        build->deleteLater();
        finish(id, error, code);
    });
    build->start();
}

void Jobs::finish(int id, const QString &error, int code)
{
    Job *job = find(id);
    if (!job)
        return;
    if (job->cancellable) {
        const bool cancelled = g_cancellable_is_cancelled(job->cancellable);
        g_object_unref(job->cancellable);
        job->cancellable = nullptr;
        if (cancelled) {
            job->state = QStringLiteral("cancelled");
            job->text = QStringLiteral("Отменено");
            Q_EMIT changed();
            next();
            return;
        }
    }
    // Окно пароля закрыли — не ошибка: просто ничего не делали.
    if (code == -1) {
        job->state = QStringLiteral("cancelled");
        job->text = error;
        Q_EMIT changed();
        next();
        return;
    }
    job->state = error.isEmpty() ? QStringLiteral("done") : QStringLiteral("failed");
    job->error = error;
    job->code = code;
    job->progress = error.isEmpty() ? 1 : -1;
    job->text = error.isEmpty() ? QStringLiteral("Готово") : error;
    const QString appId = job->appId;
    const QString name = job->name;
    const QString action = job->action;
    Q_EMIT changed();
    Q_EMIT finished(appId, name, action, error.isEmpty(), error);
    next();
}
