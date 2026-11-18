#include "prompts.h"
#include "app.h"
#include "images.h"

#include <KApplicationTrader>
#include <KFileUtils>
#include <KIO/AskUserActionInterface>
#include <KIO/Global>
#include <KIO/JobUiDelegate>
#include <KIO/JobUiDelegateFactory>
#include <KIO/OpenWithHandlerInterface>
#include <KIO/WidgetsAskUserActionHandler>
#include <KService>

#include <QCollator>
#include <QCoreApplication>
#include <QDateTime>
#include <QJSEngine>
#include <QMimeDatabase>

namespace
{
Prompts *s_instance = nullptr;

// Файл с одной из сторон конфликта — для карточки в окне.
QVariantMap fileInfo(const QUrl &url, KIO::filesize_t size, const QDateTime &modified, bool isDir)
{
    QMimeDatabase db;
    const QMimeType mime = isDir ? db.mimeTypeForName(QStringLiteral("inode/directory"))
        : url.isLocalFile()     ? db.mimeTypeForFile(url.toLocalFile())
                                : db.mimeTypeForUrl(url);
    return {
        {QStringLiteral("url"), url},
        {QStringLiteral("name"), url.fileName()},
        {QStringLiteral("folder"), url.adjusted(QUrl::RemoveFilename | QUrl::StripTrailingSlash)},
        {QStringLiteral("size"), size == KIO::filesize_t(-1) ? -1.0 : qreal(size)},
        {QStringLiteral("modified"), modified},
        {QStringLiteral("mimeType"), mime.name()},
        {QStringLiteral("iconName"), KIO::iconNameForUrl(url)},
        {QStringLiteral("canPreview"), !isDir && canPreview(mime.name())},
        {QStringLiteral("isDir"), isDir},
    };
}

QVariantMap appInfo(const KService::Ptr &service)
{
    // Что это за программа; часто совпадает с именем — тогда не повторяем.
    const QString comment = service->genericName().isEmpty() ? service->comment() : service->genericName();
    return {
        {QStringLiteral("id"), service->storageId()},
        {QStringLiteral("name"), service->name()},
        {QStringLiteral("icon"), service->icon()},
        {QStringLiteral("comment"), comment == service->name() ? QString() : comment},
    };
}

// «Файл уже есть» и «не получилось — пропустить?» — наши окна. Остальное
// (подтверждение удаления, SSL, прочие сообщения) у нас не спрашивается,
// а если спросится — отдаём штатному обработчику KIO.
class AskHandler : public KIO::AskUserActionInterface
{
public:
    AskHandler()
        : m_fallback(new KIO::WidgetsAskUserActionHandler(this))
    {
        connect(m_fallback, &AskUserActionInterface::askUserDeleteResult, this, &AskUserActionInterface::askUserDeleteResult);
        connect(m_fallback, &AskUserActionInterface::messageBoxResult, this, &AskUserActionInterface::messageBoxResult);
        connect(m_fallback, &AskUserActionInterface::askIgnoreSslErrorsResult, this, &AskUserActionInterface::askIgnoreSslErrorsResult);
    }

    void askUserRename(KJob *job,
                       const QString &,
                       const QUrl &src,
                       const QUrl &dest,
                       KIO::RenameDialog_Options options,
                       KIO::filesize_t sizeSrc,
                       KIO::filesize_t sizeDest,
                       const QDateTime &,
                       const QDateTime &,
                       const QDateTime &mtimeSrc,
                       const QDateTime &mtimeDest) override
    {
        const bool srcIsDir = options & KIO::RenameDialog_SourceIsDirectory;
        const bool destIsDir = options & KIO::RenameDialog_DestIsDirectory;
        const bool itself = options & KIO::RenameDialog_OverwriteItself;
        const QUrl destFolder = dest.adjusted(QUrl::RemoveFilename);
        const QString suggested = KFileUtils::suggestName(destFolder, dest.fileName());

        const QVariantMap question{
            {QStringLiteral("kind"), QStringLiteral("conflict")},
            {QStringLiteral("source"), fileInfo(src, sizeSrc, mtimeSrc, srcIsDir)},
            {QStringLiteral("dest"), fileInfo(dest, sizeDest, mtimeDest, destIsDir)},
            {QStringLiteral("itself"), itself},
            {QStringLiteral("merge"), srcIsDir && destIsDir},
            {QStringLiteral("canReplace"), bool(options & KIO::RenameDialog_Overwrite) && !itself},
            {QStringLiteral("canSkip"), bool(options & KIO::RenameDialog_Skip)},
            {QStringLiteral("canRename"), !(options & KIO::RenameDialog_NoRename)},
            {QStringLiteral("multiple"), bool(options & KIO::RenameDialog_MultipleItems)},
            {QStringLiteral("suggestedName"), suggested},
        };

        QPointer<KJob> guard(job);
        Prompts::instance()->ask(this, question, [this, guard, destFolder, suggested](const QVariantMap &answer) {
            const QString choice = answer.value(QStringLiteral("choice")).toString();
            const bool all = answer.value(QStringLiteral("all")).toBool();
            KIO::RenameDialog_Result result = KIO::Result_Cancel;
            QUrl newUrl;
            if (choice == QLatin1String("replace")) {
                result = all ? KIO::Result_OverwriteAll : KIO::Result_Overwrite;
            } else if (choice == QLatin1String("skip")) {
                result = all ? KIO::Result_AutoSkip : KIO::Result_Skip;
            } else if (choice == QLatin1String("rename")) {
                result = all ? KIO::Result_AutoRename : KIO::Result_Rename;
                QString name = answer.value(QStringLiteral("name")).toString().trimmed();
                if (name.isEmpty())
                    name = suggested;
                newUrl = destFolder;
                newUrl.setPath(newUrl.path() + name);
            }
            Q_EMIT askUserRenameResult(result, newUrl, guard);
        });
    }

    void askUserSkip(KJob *job, KIO::SkipDialog_Options options, const QString &errorText) override
    {
        const QVariantMap question{
            {QStringLiteral("kind"), QStringLiteral("skip")},
            {QStringLiteral("text"), errorText},
            {QStringLiteral("multiple"), bool(options & KIO::SkipDialog_MultipleItems)},
            {QStringLiteral("canRetry"), !(options & KIO::SkipDialog_Hide_Retry)},
            {QStringLiteral("canReplaceChars"), bool(options & KIO::SkipDialog_Replace_Invalid_Chars)},
        };
        QPointer<KJob> guard(job);
        Prompts::instance()->ask(this, question, [this, guard](const QVariantMap &answer) {
            const QString choice = answer.value(QStringLiteral("choice")).toString();
            const bool all = answer.value(QStringLiteral("all")).toBool();
            KIO::SkipDialog_Result result = KIO::Result_Cancel;
            if (choice == QLatin1String("skip"))
                result = all ? KIO::Result_AutoSkip : KIO::Result_Skip;
            else if (choice == QLatin1String("retry"))
                result = KIO::Result_Retry;
            else if (choice == QLatin1String("replaceChars"))
                result = all ? KIO::Result_ReplaceAllInvalidChars : KIO::Result_ReplaceInvalidChars;
            Q_EMIT askUserSkipResult(result, guard);
        });
    }

    void askUserDelete(const QList<QUrl> &urls, DeletionType deletionType, ConfirmationType confirmationType, QWidget *parent) override
    {
        m_fallback->askUserDelete(urls, deletionType, confirmationType, parent);
    }

    void requestUserMessageBox(MessageDialogType type,
                               const QString &text,
                               const QString &title,
                               const QString &primaryActionText,
                               const QString &secondaryActionText,
                               const QString &primaryActionIconName,
                               const QString &secondaryActionIconName,
                               const QString &dontAskAgainName,
                               const QString &details,
                               QWidget *parent) override
    {
        m_fallback->requestUserMessageBox(type, text, title, primaryActionText, secondaryActionText, primaryActionIconName,
                                          secondaryActionIconName, dontAskAgainName, details, parent);
    }

    void askIgnoreSslErrors(const QVariantMap &sslErrorData, QWidget *parent) override
    {
        m_fallback->askIgnoreSslErrors(sslErrorData, parent);
    }

private:
    KIO::WidgetsAskUserActionHandler *m_fallback;
};

// «Чем открыть?» — когда у типа файла нет программы или выбрали «Другая программа…».
class OpenWithHandler : public KIO::OpenWithHandlerInterface
{
public:
    void promptUserForApplication(KJob *, const QList<QUrl> &urls, const QString &mimeType) override
    {
        QMimeDatabase db;
        const QMimeType mime = db.mimeTypeForName(mimeType);
        QVariantList apps;
        if (!mimeType.isEmpty()) {
            const KService::List services = KApplicationTrader::queryByMimeType(mimeType);
            for (const KService::Ptr &service : services)
                apps.append(appInfo(service));
        }
        const QVariantMap question{
            {QStringLiteral("kind"), QStringLiteral("openWith")},
            {QStringLiteral("mimeType"), mimeType},
            {QStringLiteral("typeName"), mime.isValid() ? mime.comment() : QString()},
            {QStringLiteral("name"), urls.isEmpty() ? QString() : urls.constFirst().fileName()},
            {QStringLiteral("count"), urls.size()},
            {QStringLiteral("apps"), apps},
        };
        Prompts::instance()->ask(this, question, [this, mimeType](const QVariantMap &answer) {
            const KService::Ptr service = KService::serviceByStorageId(answer.value(QStringLiteral("id")).toString());
            if (!service) {
                Q_EMIT canceled();
                return;
            }
            if (answer.value(QStringLiteral("remember")).toBool() && !mimeType.isEmpty())
                KApplicationTrader::setPreferredService(mimeType, service);
            Q_EMIT serviceSelected(service);
        });
    }
};

// Штатный делегат KIO (ошибки, окно задания), но с нашими обработчиками.
class Delegate : public KIO::JobUiDelegate
{
public:
    Delegate(KJobUiDelegate::Flags flags, QWidget *window)
        : KIO::JobUiDelegate(flags, window, {new AskHandler, new OpenWithHandler})
    {
    }
};

class DelegateFactory : public KIO::JobUiDelegateFactory
{
public:
    KJobUiDelegate *createDelegate() const override
    {
        return createDelegate(KJobUiDelegate::AutoHandlingDisabled, nullptr);
    }

    KJobUiDelegate *createDelegate(KJobUiDelegate::Flags flags, QWidget *window) const override
    {
        return new Delegate(flags, window);
    }
};
} // namespace

Prompts::Prompts(QObject *parent)
    : QObject(parent)
{
}

Prompts *Prompts::instance()
{
    if (!s_instance)
        s_instance = new Prompts(QCoreApplication::instance());
    return s_instance;
}

Prompts *Prompts::create(QQmlEngine *, QJSEngine *)
{
    Prompts *prompts = instance();
    QJSEngine::setObjectOwnership(prompts, QJSEngine::CppOwnership);
    return prompts;
}

void Prompts::install()
{
    static DelegateFactory factory;
    KIO::setDefaultJobUiDelegateFactory(&factory);
}

QVariantMap Prompts::current() const
{
    return m_queue.isEmpty() ? QVariantMap() : m_queue.constFirst().question;
}

void Prompts::ask(QObject *owner, const QVariantMap &question, const Reply &reply)
{
    m_queue.append({owner, question, reply});
    // Задание отменили, пока вопрос висит, — снимаем его.
    connect(owner, &QObject::destroyed, this, &Prompts::ownerDestroyed, Qt::UniqueConnection);
    if (m_queue.size() == 1)
        showFirst();
}

void Prompts::answer(const QVariantMap &answer)
{
    if (m_queue.isEmpty())
        return;
    const Pending pending = m_queue.takeFirst();
    // Ответ может тут же вызвать следующий вопрос того же задания.
    if (pending.owner)
        pending.reply(answer);
    m_queue.removeIf([](const Pending &p) {
        return !p.owner;
    });
    showFirst();
}

void Prompts::ownerDestroyed()
{
    // QPointer обнуляется до конца удаления — проверяем после.
    QMetaObject::invokeMethod(this, [this] {
        const bool firstGone = !m_queue.isEmpty() && !m_queue.constFirst().owner;
        m_queue.removeIf([](const Pending &p) {
            return !p.owner;
        });
        if (firstGone)
            showFirst();
    }, Qt::QueuedConnection);
}

void Prompts::showFirst()
{
    if (!m_queue.isEmpty())
        m_parentWindow = App::instance() ? App::instance()->lastWindow() : nullptr;
    Q_EMIT currentChanged();
}

QVariantList Prompts::allApplications() const
{
    KService::List services = KApplicationTrader::query([](const KService::Ptr &service) {
        return !service->noDisplay() && !service->exec().isEmpty();
    });
    QCollator collator;
    collator.setCaseSensitivity(Qt::CaseInsensitive);
    std::sort(services.begin(), services.end(), [&collator](const KService::Ptr &a, const KService::Ptr &b) {
        return collator.compare(a->name(), b->name()) < 0;
    });
    QVariantList list;
    for (const KService::Ptr &service : std::as_const(services))
        list.append(appInfo(service));
    return list;
}
