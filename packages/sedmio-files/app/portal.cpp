#include "portal.h"

#include <KWindowSystem>

#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusMetaType>
#include <QDBusPendingCallWatcher>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QQuickWindow>
#include <QUrl>

#include <cstdio>
#include <limits>

using namespace Portal;

// ---- Типы D-Bus

QDBusArgument &operator<<(QDBusArgument &arg, const FilterRule &rule)
{
    arg.beginStructure();
    arg << rule.type << rule.pattern;
    arg.endStructure();
    return arg;
}

const QDBusArgument &operator>>(const QDBusArgument &arg, FilterRule &rule)
{
    arg.beginStructure();
    arg >> rule.type >> rule.pattern;
    arg.endStructure();
    return arg;
}

QDBusArgument &operator<<(QDBusArgument &arg, const Filter &filter)
{
    arg.beginStructure();
    arg << filter.name << filter.rules;
    arg.endStructure();
    return arg;
}

const QDBusArgument &operator>>(const QDBusArgument &arg, Filter &filter)
{
    arg.beginStructure();
    arg >> filter.name >> filter.rules;
    arg.endStructure();
    return arg;
}

QDBusArgument &operator<<(QDBusArgument &arg, const ChoiceItem &item)
{
    arg.beginStructure();
    arg << item.id << item.label;
    arg.endStructure();
    return arg;
}

const QDBusArgument &operator>>(const QDBusArgument &arg, ChoiceItem &item)
{
    arg.beginStructure();
    arg >> item.id >> item.label;
    arg.endStructure();
    return arg;
}

QDBusArgument &operator<<(QDBusArgument &arg, const Choice &choice)
{
    arg.beginStructure();
    arg << choice.id << choice.label << choice.items << choice.initial;
    arg.endStructure();
    return arg;
}

const QDBusArgument &operator>>(const QDBusArgument &arg, Choice &choice)
{
    arg.beginStructure();
    arg >> choice.id >> choice.label >> choice.items >> choice.initial;
    arg.endStructure();
    return arg;
}

namespace
{
const QString serviceName = QStringLiteral("org.freedesktop.impl.portal.desktop.sedmio");
const QString objectPath = QStringLiteral("/org/freedesktop/portal/desktop");
// Окно KDE (xdg-desktop-portal-kde) — запасное, если своё не создалось.
const QString kdeService = QStringLiteral("org.freedesktop.impl.portal.desktop.kde");
const QString chooserInterface = QStringLiteral("org.freedesktop.impl.portal.FileChooser");
const QString requestInterface = QStringLiteral("org.freedesktop.impl.portal.Request");

enum Response : uint { Success = 0, Cancelled = 1, Failed = 2 };

// Сколько ждать без окон, прежде чем выйти.
constexpr int idleTimeout = 60 * 1000;

template<typename T>
T option(const QVariantMap &options, const char *key)
{
    const QVariant value = options.value(QString::fromLatin1(key));
    if (value.userType() == qMetaTypeId<QDBusArgument>())
        return qdbus_cast<T>(value.value<QDBusArgument>());
    return value.value<T>();
}

// ay с нулём на конце → путь.
QString pathOption(const QVariantMap &options, const char *key)
{
    QByteArray bytes = options.value(QString::fromLatin1(key)).toByteArray();
    while (bytes.endsWith('\0'))
        bytes.chop(1);
    return bytes.isEmpty() ? QString() : QFile::decodeName(bytes);
}

// «_Открыть» (GTK) и «&Открыть» (Qt) → «Открыть»; «__» и «&&» — сам знак.
QString withoutMnemonic(const QString &label)
{
    QString out;
    for (qsizetype i = 0; i < label.size(); ++i) {
        const QChar c = label.at(i);
        if ((c == QLatin1Char('_') || c == QLatin1Char('&')) && i + 1 < label.size()) {
            if (label.at(i + 1) == c)
                ++i;
            else
                continue;
        }
        out += c;
    }
    return out;
}

QVariantList filtersForQml(const QList<Filter> &filters)
{
    QVariantList list;
    for (const Filter &filter : filters) {
        QStringList patterns;
        QStringList mimes;
        for (const FilterRule &rule : filter.rules)
            (rule.type == 1 ? mimes : patterns) << rule.pattern;
        list << QVariantMap{{QStringLiteral("name"), filter.name},
                            {QStringLiteral("patterns"), patterns},
                            {QStringLiteral("mimes"), mimes}};
    }
    return list;
}

QVariantList choicesForQml(const QList<Choice> &choices)
{
    QVariantList list;
    for (const Choice &choice : choices) {
        QVariantList items;
        for (const ChoiceItem &item : choice.items)
            items << QVariantMap{{QStringLiteral("id"), item.id}, {QStringLiteral("label"), item.label}};
        list << QVariantMap{{QStringLiteral("id"), choice.id},
                            {QStringLiteral("label"), withoutMnemonic(choice.label)},
                            {QStringLiteral("items"), items},
                            {QStringLiteral("initial"), choice.initial}};
    }
    return list;
}

void registerTypes()
{
    qDBusRegisterMetaType<FilterRule>();
    qDBusRegisterMetaType<QList<FilterRule>>();
    qDBusRegisterMetaType<Filter>();
    qDBusRegisterMetaType<QList<Filter>>();
    qDBusRegisterMetaType<ChoiceItem>();
    qDBusRegisterMetaType<QList<ChoiceItem>>();
    qDBusRegisterMetaType<Choice>();
    qDBusRegisterMetaType<QList<Choice>>();
    qDBusRegisterMetaType<QList<QByteArray>>();
}
} // namespace

// ---- Один открытый диалог: отвечает порталу, когда окно закроется.

class ChooserSession : public QObject
{
    Q_OBJECT

public:
    ChooserSession(const QDBusMessage &message, const QList<Filter> &filters, QObject *parent)
        : QObject(parent)
        , m_message(message)
        , m_filters(filters)
    {
    }

    ~ChooserSession() override
    {
        // Окно пропало, не ответив (не должно быть) — сказать, что не вышло.
        reply(Failed, {});
    }

    void setWindow(QQuickWindow *window) { m_window = window; }
    // Ответит кто-то другой (окно KDE).
    void forgetReply() { m_replied = true; }

    // Из QML: выбрали (uris) или отменили.
    Q_INVOKABLE void finish(bool accepted, const QVariantList &uris, int filterIndex, const QVariantMap &choices)
    {
        if (!accepted) {
            reply(Cancelled, {});
        } else {
            QStringList list;
            for (const QVariant &uri : uris)
                list << uri.toUrl().toString(QUrl::FullyEncoded);
            QVariantMap results{{QStringLiteral("uris"), list}};
            if (filterIndex >= 0 && filterIndex < m_filters.size())
                results.insert(QStringLiteral("current_filter"), QVariant::fromValue(m_filters.at(filterIndex)));
            if (!choices.isEmpty()) {
                QList<ChoiceItem> selected;
                for (auto it = choices.begin(); it != choices.end(); ++it)
                    selected << ChoiceItem{it.key(), it.value().toString()};
                results.insert(QStringLiteral("choices"), QVariant::fromValue(selected));
            }
            reply(list.isEmpty() ? Cancelled : Success, results);
        }
        close();
    }

    // Портал отменил просьбу (Request.Close).
    void cancel()
    {
        reply(Cancelled, {});
        close();
    }

    // Что лежит по адресу: 0 — ничего, 1 — файл, 2 — папка. Только свой диск:
    // программам отдаём пути, а не адреса KIO.
    Q_INVOKABLE int kind(const QUrl &url) const
    {
        if (!url.isLocalFile())
            return 0;
        const QFileInfo info(url.toLocalFile());
        return !info.exists() ? 0 : info.isDir() ? 2 : 1;
    }

    // Ввели имя или путь: относительно папки, «~» — домашняя.
    Q_INVOKABLE QUrl resolve(const QUrl &folder, const QString &text) const
    {
        QString path = text.trimmed();
        if (path == QLatin1String("~") || path.startsWith(QLatin1String("~/")))
            path = QDir::homePath() + path.mid(1);
        if (!QDir::isAbsolutePath(path))
            path = folder.toLocalFile() + QLatin1Char('/') + path;
        return QUrl::fromLocalFile(QDir::cleanPath(path));
    }

    Q_INVOKABLE QUrl parentOf(const QUrl &url) const
    {
        return QUrl::fromLocalFile(QFileInfo(url.toLocalFile()).absolutePath());
    }

Q_SIGNALS:
    void closed();

private:
    void reply(uint response, const QVariantMap &results)
    {
        if (m_replied)
            return;
        m_replied = true;
        QDBusConnection::sessionBus().send(m_message.createReply({QVariant::fromValue(response), results}));
    }

    void close()
    {
        if (m_window) {
            m_window->hide();
            m_window->deleteLater();
            m_window = nullptr;
        }
        Q_EMIT closed();
    }

    QDBusMessage m_message;
    QList<Filter> m_filters;
    QPointer<QQuickWindow> m_window;
    bool m_replied = false;
};

// ---- Request

PortalRequest::PortalRequest(const QDBusObjectPath &handle, QObject *parent)
    : QObject(parent)
    , m_path(handle.path())
{
    QDBusConnection::sessionBus().registerObject(m_path, this, QDBusConnection::ExportScriptableSlots);
}

PortalRequest::~PortalRequest()
{
    QDBusConnection::sessionBus().unregisterObject(m_path);
}

void PortalRequest::Close()
{
    Q_EMIT closeRequested();
}

// ---- FileChooser

FileChooserPortal::FileChooserPortal(QQmlEngine *engine)
    : QObject(engine)
    , m_engine(engine)
{
    registerTypes();
    m_idle.setSingleShot(true);
    m_idle.setInterval(idleTimeout);
    connect(&m_idle, &QTimer::timeout, qApp, &QCoreApplication::quit);
    m_idle.start();
}

bool FileChooserPortal::registerOnBus()
{
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.isConnected())
        return false;
    if (!bus.registerObject(objectPath, this, QDBusConnection::ExportScriptableSlots))
        return false;
    return bus.registerService(serviceName);
}

uint FileChooserPortal::OpenFile(const QDBusObjectPath &handle, const QString &, const QString &parent_window, const QString &title,
                                 const QVariantMap &options, QVariantMap &)
{
    show(QStringLiteral("open"), handle, parent_window, title, options);
    return 0;
}

uint FileChooserPortal::SaveFile(const QDBusObjectPath &handle, const QString &, const QString &parent_window, const QString &title,
                                 const QVariantMap &options, QVariantMap &)
{
    show(QStringLiteral("save"), handle, parent_window, title, options);
    return 0;
}

uint FileChooserPortal::SaveFiles(const QDBusObjectPath &handle, const QString &, const QString &parent_window, const QString &title,
                                  const QVariantMap &options, QVariantMap &)
{
    show(QStringLiteral("saveFiles"), handle, parent_window, title, options);
    return 0;
}

void FileChooserPortal::show(const QString &mode, const QDBusObjectPath &handle, const QString &parentWindow, const QString &title,
                             const QVariantMap &options)
{
    // Ответ — когда окно закроется.
    setDelayedReply(true);
    const QDBusMessage call = message();

    const QList<Filter> filters = option<QList<Filter>>(options, "filters");
    int currentFilter = filters.isEmpty() ? -1 : 0;
    if (options.contains(QStringLiteral("current_filter"))) {
        const Filter current = option<Filter>(options, "current_filter");
        for (int i = 0; i < filters.size(); ++i) {
            if (filters.at(i).name == current.name) {
                currentFilter = i;
                break;
            }
        }
    }

    QString folder = pathOption(options, "current_folder");
    QString name = options.value(QStringLiteral("current_name")).toString();
    const QString file = pathOption(options, "current_file");
    if (!file.isEmpty()) {
        const QFileInfo info(file);
        folder = info.absolutePath();
        name = info.fileName();
    }
    QStringList files;
    for (const QByteArray &bytes : option<QList<QByteArray>>(options, "files")) {
        QByteArray b = bytes;
        while (b.endsWith('\0'))
            b.chop(1);
        if (!b.isEmpty())
            files << QFileInfo(QFile::decodeName(b)).fileName();
    }

    auto *session = new ChooserSession(call, filters, this);
    auto *request = new PortalRequest(handle, session);
    connect(request, &PortalRequest::closeRequested, session, &ChooserSession::cancel);

    const QVariantMap properties{
        {QStringLiteral("session"), QVariant::fromValue<QObject *>(session)},
        {QStringLiteral("mode"), mode},
        {QStringLiteral("requestedTitle"), title},
        {QStringLiteral("acceptLabel"), withoutMnemonic(options.value(QStringLiteral("accept_label")).toString())},
        {QStringLiteral("multiple"), options.value(QStringLiteral("multiple")).toBool()},
        {QStringLiteral("directory"), options.value(QStringLiteral("directory")).toBool()},
        {QStringLiteral("filters"), filtersForQml(filters)},
        {QStringLiteral("filterIndex"), currentFilter},
        {QStringLiteral("choices"), choicesForQml(option<QList<Choice>>(options, "choices"))},
        {QStringLiteral("startFolder"), folder.isEmpty() ? QUrl() : QUrl::fromLocalFile(folder)},
        {QStringLiteral("currentName"), name},
        {QStringLiteral("files"), files},
    };

    QQmlComponent component(m_engine, QStringLiteral("Sedmio.Files"), QStringLiteral("ChooserWindow"));
    QObject *object = component.createWithInitialProperties(properties);
    auto *window = qobject_cast<QQuickWindow *>(object);
    if (!window) {
        // Сломалось своё окно (QML после обновления и т. п.) — пусть
        // выберут в окне KDE, чем совсем без окна.
        std::fprintf(stderr, "sedmio-files: окно выбора файлов не создалось, беру окно KDE: %s\n", qPrintable(component.errorString()));
        delete object;
        session->forgetReply();
        delete session;
        forwardToKde(call, handle);
        return;
    }
    QQmlEngine::setObjectOwnership(window, QQmlEngine::CppOwnership);
    session->setWindow(window);

    ++m_open;
    m_idle.stop();
    connect(session, &ChooserSession::closed, this, [this, session] {
        session->deleteLater();
        --m_open;
        windowsChanged();
    });

    // Поверх окна программы, которая спросила: «wayland:ключ» (xdg-foreign)
    // или «x11:номер окна» в шестнадцатеричном виде.
    if (parentWindow.startsWith(QLatin1String("wayland:"))) {
        KWindowSystem::setMainWindow(window, parentWindow.mid(8));
    } else if (parentWindow.startsWith(QLatin1String("x11:"))) {
        bool ok = false;
        const WId id = parentWindow.mid(4).toULongLong(&ok, 16);
        if (ok)
            KWindowSystem::setMainWindow(window, id);
    }
    window->show();
    window->requestActivate();
}

void FileChooserPortal::forwardToKde(const QDBusMessage &call, const QDBusObjectPath &handle)
{
    QDBusConnection bus = QDBusConnection::sessionBus();
    QDBusMessage forward = QDBusMessage::createMethodCall(kdeService, objectPath, chooserInterface, call.member());
    forward.setArguments(call.arguments());
    // Окно открыто, пока человек выбирает: ждать без предела.
    auto *watcher = new QDBusPendingCallWatcher(bus.asyncCall(forward, std::numeric_limits<int>::max()), this);

    // Портал отменил просьбу — отменить и в окне KDE (та же ручка у него).
    auto *request = new PortalRequest(handle, watcher);
    connect(request, &PortalRequest::closeRequested, this, [path = handle.path()] {
        QDBusConnection::sessionBus().call(QDBusMessage::createMethodCall(kdeService, path, requestInterface, QStringLiteral("Close")),
                                           QDBus::NoBlock);
    });

    ++m_open;
    m_idle.stop();
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, call, watcher] {
        const QDBusMessage reply = watcher->reply();
        if (reply.type() == QDBusMessage::ReplyMessage)
            QDBusConnection::sessionBus().send(call.createReply(reply.arguments()));
        else
            QDBusConnection::sessionBus().send(call.createReply({QVariant::fromValue(uint(Failed)), QVariantMap()}));
        watcher->deleteLater();
        --m_open;
        windowsChanged();
    });
}

void FileChooserPortal::windowsChanged()
{
    if (m_open <= 0)
        m_idle.start();
}

#include "portal.moc"
