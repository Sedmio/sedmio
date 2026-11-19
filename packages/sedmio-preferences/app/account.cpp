#include "account.h"

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusObjectPath>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusReply>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QImage>
#include <QImageReader>
#include <QProcess>
#include <QRegularExpression>
#include <QTemporaryFile>

#include <crypt.h>
#include <unistd.h>

#include <memory>

namespace
{
const QString service = QStringLiteral("org.freedesktop.Accounts");
const QString userInterface = QStringLiteral("org.freedesktop.Accounts.User");
const QString greetdConfig = QStringLiteral("/etc/greetd/sedmio.toml");
const QString autologinHelper = QStringLiteral("/usr/lib/sedmio/set-autologin");
// Ждём, пока человек введёт пароль в окне polkit.
constexpr int authTimeout = 5 * 60 * 1000;

// Хэш пароля для /etc/shadow — как у passwd: способ и соль по умолчанию
// системы (на Arch — yescrypt).
QByteArray hashPassword(const QString &password)
{
    char *salt = crypt_gensalt_ra(nullptr, 0, nullptr, 0);
    if (!salt)
        return {};
    auto data = std::make_unique<crypt_data>();
    QByteArray utf8 = password.toUtf8();
    const char *hash = crypt_r(utf8.constData(), salt, data.get());
    free(salt);
    QByteArray result;
    if (hash && hash[0] != '*')
        result = hash;
    utf8.fill('\0');
    explicit_bzero(data.get(), sizeof(crypt_data));
    return result;
}

QString errorText(const QDBusError &error)
{
    const QString name = error.name();
    if (name.endsWith(QLatin1String("PermissionDenied")) || name.endsWith(QLatin1String("NotAuthorized"))
        || name == QLatin1String("org.freedesktop.DBus.Error.AccessDenied"))
        return QStringLiteral("не подтверждено паролем");
    if (error.type() == QDBusError::NoReply || error.type() == QDBusError::Timeout)
        return QStringLiteral("служба учётных записей не ответила");
    return error.message().isEmpty() ? error.name() : error.message();
}
} // namespace

Account::Account(QObject *parent)
    : QObject(parent)
{
    QDBusConnection bus = QDBusConnection::systemBus();
    QDBusMessage find = QDBusMessage::createMethodCall(service, QStringLiteral("/org/freedesktop/Accounts"), service, QStringLiteral("FindUserById"));
    find << qint64(getuid());
    const QDBusReply<QDBusObjectPath> path = bus.call(find, QDBus::Block, 5000);
    if (path.isValid()) {
        m_path = path.value().path();
        bus.connect(service, m_path, userInterface, QStringLiteral("Changed"), this, SLOT(reload()));
    } else {
        qWarning() << "account: AccountsService:" << path.error().message();
    }

    // Файл greetd подменяется целиком (rename) — следим за каталогом.
    m_watcher.addPath(QFileInfo(greetdConfig).absolutePath());
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, this, [this] {
        const QString before = m_autologinUser;
        readAutologin();
        if (before != m_autologinUser)
            Q_EMIT changed();
    });

    reload();
}

Account::~Account()
{
    delete m_avatarFile;
}

void Account::reload()
{
    readAutologin();
    if (!m_path.isEmpty()) {
        QDBusMessage get = QDBusMessage::createMethodCall(service, m_path, QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("GetAll"));
        get << userInterface;
        const QDBusReply<QVariantMap> reply = QDBusConnection::systemBus().call(get, QDBus::Block, 5000);
        if (reply.isValid()) {
            const QVariantMap props = reply.value();
            m_userName = props.value(QStringLiteral("UserName")).toString();
            m_realName = props.value(QStringLiteral("RealName")).toString();
            const QString icon = props.value(QStringLiteral("IconFile")).toString();
            // Тот же путь после смены картинки — новая версия для QML.
            m_iconFile = icon;
            ++m_revision;
        }
    }
    Q_EMIT changed();
}

QUrl Account::avatar() const
{
    if (m_iconFile.isEmpty() || !QFile::exists(m_iconFile))
        return {};
    QUrl url = QUrl::fromLocalFile(m_iconFile);
    url.setQuery(QStringLiteral("r=%1").arg(m_revision));
    return url;
}

bool Account::autologinAvailable() const
{
    return QFile::exists(autologinHelper) && QFile::exists(greetdConfig);
}

void Account::readAutologin()
{
    // [initial_session] … user = "имя" — как пишут установщик и set-autologin.
    m_autologinUser.clear();
    QFile file(greetdConfig);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return;
    static const QRegularExpression section(QStringLiteral("^\\s*\\[([^\\]]+)\\]"));
    static const QRegularExpression user(QStringLiteral("^\\s*user\\s*=\\s*\"([^\"]*)\""));
    bool inside = false;
    while (!file.atEnd()) {
        const QString line = QString::fromUtf8(file.readLine());
        if (const auto match = section.match(line); match.hasMatch()) {
            inside = match.captured(1).trimmed() == QLatin1String("initial_session");
            continue;
        }
        if (inside) {
            if (const auto match = user.match(line); match.hasMatch())
                m_autologinUser = match.captured(1);
        }
    }
}

void Account::call(const QString &method, const QVariantList &args, const QString &done, const std::function<void(bool)> &after)
{
    if (m_path.isEmpty()) {
        finish(QStringLiteral("Служба учётных записей недоступна."), true);
        return;
    }
    QDBusMessage message = QDBusMessage::createMethodCall(service, m_path, userInterface, method);
    message.setArguments(args);
    message.setInteractiveAuthorizationAllowed(true);
    m_busy = true;
    m_message.clear();
    Q_EMIT changed();
    auto *watcher = new QDBusPendingCallWatcher(QDBusConnection::systemBus().asyncCall(message, authTimeout), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, watcher, done, after] {
        watcher->deleteLater();
        const QDBusPendingReply<> reply = *watcher;
        m_busy = false;
        if (reply.isError())
            finish(QStringLiteral("Не получилось: %1.").arg(errorText(reply.error())), true);
        else
            finish(done, false);
        if (after)
            after(!reply.isError());
    });
}

void Account::finish(const QString &message, bool error)
{
    m_message = message;
    m_messageIsError = error;
    Q_EMIT changed();
}

void Account::clearMessage()
{
    if (m_message.isEmpty())
        return;
    m_message.clear();
    Q_EMIT changed();
}

void Account::setRealName(const QString &name)
{
    const QString trimmed = name.simplified();
    // Двоеточие и запятая ломают /etc/passwd (поле GECOS).
    if (trimmed == m_realName || trimmed.contains(QLatin1Char(':')) || trimmed.contains(QLatin1Char(',')))
        return;
    call(QStringLiteral("SetRealName"), {trimmed}, QStringLiteral("Имя сохранено."));
}

void Account::setAvatar(const QUrl &file)
{
    // Квадрат из середины, 512 × 512 PNG: AccountsService не берёт файлы
    // больше мегабайта, а фото с телефона — несколько мегабайт.
    QImageReader reader(file.toLocalFile());
    reader.setAutoTransform(true);
    QImage image = reader.read();
    if (image.isNull()) {
        finish(QStringLiteral("Не получилось открыть картинку."), true);
        return;
    }
    const int side = qMin(image.width(), image.height());
    image = image.copy((image.width() - side) / 2, (image.height() - side) / 2, side, side);
    if (side > 512)
        image = image.scaled(512, 512, Qt::IgnoreAspectRatio, Qt::SmoothTransformation);

    delete m_avatarFile;
    m_avatarFile = new QTemporaryFile(QDir::tempPath() + QStringLiteral("/sedmio-avatar-XXXXXX.png"));
    if (!m_avatarFile->open() || !image.save(m_avatarFile, "PNG")) {
        finish(QStringLiteral("Не получилось подготовить картинку."), true);
        return;
    }
    m_avatarFile->close();
    m_avatarFile->setPermissions(QFile::ReadOwner | QFile::WriteOwner | QFile::ReadGroup | QFile::ReadOther);
    call(QStringLiteral("SetIconFile"), {m_avatarFile->fileName()}, QStringLiteral("Картинка сохранена."), [this](bool) {
        delete m_avatarFile;
        m_avatarFile = nullptr;
        reload();
    });
}

void Account::removeAvatar()
{
    call(QStringLiteral("SetIconFile"), {QString()}, QStringLiteral("Картинка убрана."), [this](bool) { reload(); });
}

void Account::changePassword(const QString &password)
{
    if (password.isEmpty()) {
        finish(QStringLiteral("Пароль не может быть пустым."), true);
        return;
    }
    const QByteArray hash = hashPassword(password);
    if (hash.isEmpty()) {
        finish(QStringLiteral("Не получилось зашифровать пароль."), true);
        return;
    }
    call(QStringLiteral("SetPassword"), {QString::fromLatin1(hash), QString()}, QStringLiteral("Пароль изменён."), [this](bool ok) {
        if (ok)
            Q_EMIT passwordChanged();
    });
}

void Account::setAutologin(bool enabled)
{
    if (!autologinAvailable() || m_busy)
        return;
    m_busy = true;
    m_message.clear();
    Q_EMIT changed();
    auto *process = new QProcess(this);
    connect(process, &QProcess::finished, this, [this, process, enabled](int code, QProcess::ExitStatus status) {
        process->deleteLater();
        m_busy = false;
        readAutologin();
        if (status != QProcess::NormalExit)
            finish(QStringLiteral("Не получилось изменить вход без пароля."), true);
        else if (code == 126 || code == 127)
            finish(QStringLiteral("Не изменено: не подтверждено паролем."), true);
        else if (code != 0)
            finish(QStringLiteral("Не получилось изменить вход без пароля."), true);
        else
            finish(enabled ? QStringLiteral("Теперь после включения компьютера рабочий стол откроется сразу.")
                           : QStringLiteral("Теперь при входе нужен пароль."),
                   false);
    });
    connect(process, &QProcess::errorOccurred, this, [this, process](QProcess::ProcessError error) {
        if (error != QProcess::FailedToStart)
            return;
        process->deleteLater();
        m_busy = false;
        finish(QStringLiteral("Не получилось запустить pkexec."), true);
    });
    process->start(QStringLiteral("pkexec"), {autologinHelper, enabled ? QStringLiteral("on") : QStringLiteral("off")});
}
