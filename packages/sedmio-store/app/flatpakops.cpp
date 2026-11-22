#include "flatpakops.h"

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QLocale>

#include <flatpak.h>

namespace FlatpakOps
{
namespace
{
const char *flathubFile = "/usr/share/sedmio/store/flathub.flatpakrepo";

// Свой цикл GLib на время вызова: libflatpak шлёт прогресс через «свой»
// контекст потока, а без него — через общий, то есть через главный поток.
class ContextScope
{
public:
    ContextScope()
        : m_context(g_main_context_new())
    {
        g_main_context_push_thread_default(m_context);
    }
    ~ContextScope()
    {
        g_main_context_pop_thread_default(m_context);
        g_main_context_unref(m_context);
    }
    ContextScope(const ContextScope &) = delete;
    ContextScope &operator=(const ContextScope &) = delete;

private:
    GMainContext *m_context;
};

QString describe(const GError *error)
{
    if (!error)
        return QStringLiteral("Flatpak: неизвестная ошибка");
    if (g_error_matches(error, G_IO_ERROR, G_IO_ERROR_CANCELLED))
        return QStringLiteral("Отменено");
    if (g_error_matches(error, FLATPAK_ERROR, FLATPAK_ERROR_ALREADY_INSTALLED))
        return QStringLiteral("Программа уже установлена");
    if (g_error_matches(error, FLATPAK_ERROR, FLATPAK_ERROR_NOT_INSTALLED))
        return QStringLiteral("Программа не установлена");
    if (g_error_matches(error, FLATPAK_ERROR, FLATPAK_ERROR_OUT_OF_SPACE))
        return QStringLiteral("Не хватает места на диске");
    if (g_error_matches(error, FLATPAK_ERROR, FLATPAK_ERROR_REF_NOT_FOUND))
        return QStringLiteral("Программы больше нет на Flathub");
    if (g_error_matches(error, FLATPAK_ERROR, FLATPAK_ERROR_PERMISSION_DENIED))
        return QStringLiteral("Нет прав: программа стоит для всех пользователей, а пароль не введён");
    const QString message = QString::fromUtf8(error->message);
    if (message.contains(QLatin1String("resolve"), Qt::CaseInsensitive) || message.contains(QLatin1String("Timeout"), Qt::CaseInsensitive)
        || message.contains(QLatin1String("network"), Qt::CaseInsensitive) || message.contains(QLatin1String("connect"), Qt::CaseInsensitive))
        return QStringLiteral("Нет связи с Flathub — проверьте интернет");
    return QStringLiteral("Flatpak: ") + message;
}

FlatpakInstallation *userInstallation(GError **error)
{
    return flatpak_installation_new_user(nullptr, error);
}

bool hasRemote(FlatpakInstallation *installation, const char *name)
{
    g_autoptr(FlatpakRemote) remote = flatpak_installation_get_remote_by_name(installation, name, nullptr, nullptr);
    return remote != nullptr;
}

QString refName(const char *ref)
{
    // app/org.mozilla.firefox/x86_64/stable → org.mozilla.firefox
    const QStringList parts = QString::fromUtf8(ref).split(u'/');
    return parts.value(1);
}

bool isRuntime(const char *ref)
{
    return qstrncmp(ref, "runtime/", 8) == 0;
}

QString sizeText(qint64 bytes)
{
    return QLocale(QLocale::Russian).formattedDataSize(bytes, 1, QLocale::DataSizeTraditionalFormat);
}

// ---- Прогресс транзакции

struct RunState {
    const Progress *progress = nullptr;
    int total = 0;
    int done = 0;
    QString verb;   // «Скачиваю», «Удаляю», «Обновляю»
};

struct OpState {
    RunState *run;
    int index;
    qint64 size;
    QString what;
};

void onProgressChanged(FlatpakTransactionProgress *progress, gpointer data)
{
    auto *op = static_cast<OpState *>(data);
    if (!op->run->progress || !*op->run->progress)
        return;
    const int percent = flatpak_transaction_progress_get_progress(progress);
    const double fraction = (op->index + percent / 100.0) / qMax(1, op->run->total);
    QString text = op->run->verb + u' ' + op->what;
    if (op->size > 0) {
        const qint64 got = qint64(flatpak_transaction_progress_get_bytes_transferred(progress));
        if (got > 0)
            text += QStringLiteral(" — %1 из %2").arg(sizeText(qMin(got, op->size)), sizeText(op->size));
    }
    (*op->run->progress)(fraction, text);
}

void onNewOperation(FlatpakTransaction *transaction, FlatpakTransactionOperation *operation, FlatpakTransactionProgress *progress,
                    gpointer data)
{
    auto *run = static_cast<RunState *>(data);
    GList *ops = flatpak_transaction_get_operations(transaction);
    run->total = int(g_list_length(ops));
    int index = g_list_index(ops, operation);
    g_list_free_full(ops, g_object_unref);
    const char *ref = flatpak_transaction_operation_get_ref(operation);
    auto *op = new OpState{run, qMax(0, index), qint64(flatpak_transaction_operation_get_download_size(operation)),
                           isRuntime(ref) ? QStringLiteral("среду ") + refName(ref) : QStringLiteral("программу")};
    flatpak_transaction_progress_set_update_frequency(progress, 300);
    g_signal_connect_data(progress, "changed", G_CALLBACK(onProgressChanged), op, [](gpointer p, GClosure *) { delete static_cast<OpState *>(p); },
                          GConnectFlags(0));
    onProgressChanged(progress, op);
}

QString runTransaction(FlatpakTransaction *transaction, const QString &verb, const Progress &progress, GCancellable *cancellable)
{
    RunState run{&progress, 1, 0, verb};
    flatpak_transaction_set_no_interaction(transaction, TRUE);
    g_signal_connect(transaction, "new-operation", G_CALLBACK(onNewOperation), &run);
    g_autoptr(GError) error = nullptr;
    const gboolean ok = flatpak_transaction_run(transaction, cancellable, &error);
    g_signal_handlers_disconnect_by_data(transaction, &run);
    return ok ? QString() : describe(error);
}

// ---- Разрешения из метаданных

void addPermissions(GKeyFile *meta, QList<std::pair<QString, bool>> &out)
{
    auto list = [meta](const char *group, const char *key) {
        QStringList values;
        gsize n = 0;
        g_auto(GStrv) items = g_key_file_get_string_list(meta, group, key, &n, nullptr);
        for (gsize i = 0; items && i < n; ++i)
            values << QString::fromUtf8(items[i]);
        return values;
    };
    const QStringList shared = list("Context", "shared");
    const QStringList sockets = list("Context", "sockets");
    const QStringList devices = list("Context", "devices");
    const QStringList filesystems = list("Context", "filesystems");
    const QStringList features = list("Context", "features");

    if (filesystems.contains(QLatin1String("host")) || filesystems.contains(QLatin1String("host:rw")))
        out.append({QStringLiteral("Все файлы компьютера"), true});
    else if (filesystems.contains(QLatin1String("home")) || filesystems.contains(QLatin1String("home:rw")))
        out.append({QStringLiteral("Вся домашняя папка"), true});
    if (filesystems.contains(QLatin1String("host-os")) || filesystems.contains(QLatin1String("host-etc")))
        out.append({QStringLiteral("Файлы и настройки системы"), true});
    if (devices.contains(QLatin1String("all")))
        out.append({QStringLiteral("Все устройства: камера, USB, геймпады"), true});
    if (sockets.contains(QLatin1String("session-bus")))
        out.append({QStringLiteral("Все службы сеанса"), true});
    if (sockets.contains(QLatin1String("system-bus")))
        out.append({QStringLiteral("Все службы системы"), true});
    if (sockets.contains(QLatin1String("x11")) && !sockets.contains(QLatin1String("wayland")))
        out.append({QStringLiteral("Старый способ вывода окон (X11): видит ввод в других таких окнах"), true});
    if (sockets.contains(QLatin1String("ssh-auth")))
        out.append({QStringLiteral("Ключи SSH"), true});
    if (sockets.contains(QLatin1String("gpg-agent")))
        out.append({QStringLiteral("Ключи GnuPG"), true});
    if (features.contains(QLatin1String("devel")))
        out.append({QStringLiteral("Отладка других программ"), true});
    {
        g_autofree char *value = g_key_file_get_string(meta, "Session Bus Policy", "org.freedesktop.Flatpak", nullptr);
        const QString talk = QString::fromUtf8(value);
        if (talk == QLatin1String("talk"))
            out.append({QStringLiteral("Запуск команд вне песочницы"), true});
    }

    if (shared.contains(QLatin1String("network")))
        out.append({QStringLiteral("Интернет"), false});
    if (sockets.contains(QLatin1String("pulseaudio")))
        out.append({QStringLiteral("Звук и микрофон"), false});
    if (sockets.contains(QLatin1String("cups")))
        out.append({QStringLiteral("Печать"), false});
    if (sockets.contains(QLatin1String("pcsc")))
        out.append({QStringLiteral("Смарт-карты"), false});
    if (devices.contains(QLatin1String("input")) && !devices.contains(QLatin1String("all")))
        out.append({QStringLiteral("Геймпады и устройства ввода"), false});
    if (devices.contains(QLatin1String("kvm")) && !devices.contains(QLatin1String("all")))
        out.append({QStringLiteral("Виртуализация (KVM)"), false});
    if (features.contains(QLatin1String("bluetooth")))
        out.append({QStringLiteral("Bluetooth"), false});
    {
        g_autofree char *value = g_key_file_get_string(meta, "Session Bus Policy", "org.freedesktop.secrets", nullptr);
        const QString secrets = QString::fromUtf8(value);
        if (secrets == QLatin1String("talk"))
            out.append({QStringLiteral("Хранилище паролей"), false});
    }

    // Отдельные папки (если не вся домашняя).
    const bool wide = std::any_of(out.cbegin(), out.cend(), [](const auto &p) {
        return p.first.startsWith(QLatin1String("Все файлы")) || p.first.startsWith(QLatin1String("Вся домашняя"));
    });
    if (wide)
        return;
    static const QList<std::pair<QString, QString>> xdg = {
        {QStringLiteral("xdg-download"), QStringLiteral("«Загрузки»")},   {QStringLiteral("xdg-documents"), QStringLiteral("«Документы»")},
        {QStringLiteral("xdg-pictures"), QStringLiteral("«Изображения»")}, {QStringLiteral("xdg-music"), QStringLiteral("«Музыка»")},
        {QStringLiteral("xdg-videos"), QStringLiteral("«Видео»")},        {QStringLiteral("xdg-desktop"), QStringLiteral("«Рабочий стол»")},
    };
    QStringList folders;
    bool readOnly = true;
    for (QString fs : filesystems) {
        if (fs.startsWith(u'!'))
            continue;
        bool ro = false;
        if (fs.endsWith(QLatin1String(":ro"))) {
            ro = true;
            fs.chop(3);
        } else if (fs.endsWith(QLatin1String(":rw")) || fs.endsWith(QLatin1String(":create"))) {
            fs = fs.section(u':', 0, 0);
        }
        QString name;
        for (const auto &[key, title] : xdg) {
            if (fs == key || fs.startsWith(key + u'/'))
                name = fs == key ? title : title + fs.mid(key.size());
        }
        if (name.isEmpty()) {
            // xdg-config/…, xdg-data/…, xdg-run/… — служебные папки программы.
            if (fs.startsWith(QLatin1String("xdg-")) || fs == QLatin1String("home") || fs.startsWith(QLatin1String("host")))
                continue;
            name = fs;
        }
        folders << name;
        readOnly = readOnly && ro;
    }
    if (!folders.isEmpty())
        out.append({(folders.size() == 1 ? QStringLiteral("Папка ") : QStringLiteral("Папки ")) + folders.join(QStringLiteral(", "))
                        + (readOnly ? QStringLiteral(" (только чтение)") : QString()),
                    false});
}

gboolean abortWhenReady(FlatpakTransaction *transaction, gpointer data)
{
    auto *result = static_cast<Preview *>(data);
    GList *ops = flatpak_transaction_get_operations(transaction);
    for (GList *l = ops; l; l = l->next) {
        auto *op = FLATPAK_TRANSACTION_OPERATION(l->data);
        const char *ref = flatpak_transaction_operation_get_ref(op);
        result->download += qint64(flatpak_transaction_operation_get_download_size(op));
        result->installed += qint64(flatpak_transaction_operation_get_installed_size(op));
        if (isRuntime(ref)) {
            const QString name = refName(ref);
            // Сами среды (org.kde.Platform), без дополнений к ним — переводов,
            // кодеков, тем, драйверов.
            if (name.endsWith(QLatin1String(".Platform")) && !result->runtimes.contains(name))
                result->runtimes << name;
        } else if (GKeyFile *meta = flatpak_transaction_operation_get_metadata(op)) {
            addPermissions(meta, result->permissions);
        }
    }
    g_list_free_full(ops, g_object_unref);
    result->ok = true;
    return FALSE; // только посмотреть
}
} // namespace

QString ensureFlathub()
{
    ContextScope scope;
    g_autoptr(GError) error = nullptr;
    g_autoptr(FlatpakInstallation) user = userInstallation(&error);
    if (!user)
        return describe(error);
    // Нужен именно у пользователя, даже если он есть в системе (пакет
    // flatpak в Arch подключает его туда): ставим к пользователю, без пароля.
    if (hasRemote(user, "flathub"))
        return {};
    QFile file(QString::fromLatin1(flathubFile));
    if (!file.open(QIODevice::ReadOnly))
        return QStringLiteral("Нет файла %1").arg(QString::fromLatin1(flathubFile));
    const QByteArray data = file.readAll();
    g_autoptr(GBytes) bytes = g_bytes_new(data.constData(), gsize(data.size()));
    g_autoptr(FlatpakRemote) remote = flatpak_remote_new_from_file("flathub", bytes, &error);
    if (!remote)
        return describe(error);
    if (!flatpak_installation_add_remote(user, remote, TRUE, nullptr, &error))
        return describe(error);
    return {};
}

QString refreshAppstream(qint64 maxAgeSecs, bool *changed)
{
    ContextScope scope;
    if (changed)
        *changed = false;
    g_autoptr(GError) error = nullptr;
    g_autoptr(FlatpakInstallation) user = userInstallation(&error);
    if (!user)
        return describe(error);
    g_autoptr(FlatpakRemote) remote = flatpak_installation_get_remote_by_name(user, "flathub", nullptr, nullptr);
    if (!remote)
        return QStringLiteral("Flathub не подключён");
    g_autoptr(GFile) stamp = flatpak_remote_get_appstream_timestamp(remote, nullptr);
    g_autofree char *path = g_file_get_path(stamp);
    const QFileInfo info(QString::fromUtf8(path));
    if (info.exists() && info.lastModified().secsTo(QDateTime::currentDateTime()) < maxAgeSecs)
        return {};
    gboolean updated = FALSE;
    if (!flatpak_installation_update_appstream_full_sync(user, "flathub", nullptr, nullptr, nullptr, &updated, nullptr, &error))
        return describe(error);
    if (changed)
        *changed = updated;
    return {};
}

Preview preview(const QString &origin, const QString &ref, GCancellable *cancellable)
{
    ContextScope scope;
    Preview result;
    g_autoptr(GError) error = nullptr;
    g_autoptr(FlatpakInstallation) user = userInstallation(&error);
    if (!user) {
        result.error = describe(error);
        return result;
    }
    g_autoptr(FlatpakTransaction) transaction = flatpak_transaction_new_for_installation(user, cancellable, &error);
    if (!transaction || !flatpak_transaction_add_install(transaction, origin.toUtf8().constData(), ref.toUtf8().constData(), nullptr, &error)) {
        result.error = describe(error);
        return result;
    }
    flatpak_transaction_set_no_interaction(transaction, TRUE);
    g_signal_connect(transaction, "ready", G_CALLBACK(abortWhenReady), &result);
    g_clear_error(&error);
    flatpak_transaction_run(transaction, cancellable, &error);
    if (!result.ok)
        result.error = describe(error);
    return result;
}

QString install(const QString &origin, const QString &ref, const Progress &progress, GCancellable *cancellable)
{
    ContextScope scope;
    g_autoptr(GError) error = nullptr;
    g_autoptr(FlatpakInstallation) user = userInstallation(&error);
    if (!user)
        return describe(error);
    g_autoptr(FlatpakTransaction) transaction = flatpak_transaction_new_for_installation(user, cancellable, &error);
    if (!transaction || !flatpak_transaction_add_install(transaction, origin.toUtf8().constData(), ref.toUtf8().constData(), nullptr, &error))
        return describe(error);
    return runTransaction(transaction, QStringLiteral("Скачиваю"), progress, cancellable);
}

QString uninstall(const QString &ref, bool user, bool deleteData, const Progress &progress, GCancellable *cancellable)
{
    ContextScope scope;
    g_autoptr(GError) error = nullptr;
    g_autoptr(FlatpakInstallation) installation = user ? userInstallation(&error) : flatpak_installation_new_system(cancellable, &error);
    if (!installation)
        return describe(error);
    g_autoptr(FlatpakTransaction) transaction = flatpak_transaction_new_for_installation(installation, cancellable, &error);
    if (!transaction || !flatpak_transaction_add_uninstall(transaction, ref.toUtf8().constData(), &error))
        return describe(error);
    const QString failure = runTransaction(transaction, QStringLiteral("Удаляю"), progress, cancellable);
    if (failure.isEmpty() && deleteData) {
        const QString id = refName(ref.toUtf8().constData());
        if (!id.isEmpty())
            QDir(QDir::homePath() + QStringLiteral("/.var/app/") + id).removeRecursively();
    }
    // Ненужные больше среды выполнения — тоже (как flatpak uninstall --unused).
    if (failure.isEmpty()) {
        g_autoptr(FlatpakTransaction) cleanup = flatpak_transaction_new_for_installation(installation, cancellable, nullptr);
        g_autoptr(GPtrArray) unused = flatpak_installation_list_unused_refs(installation, nullptr, cancellable, nullptr);
        if (cleanup && unused && unused->len > 0) {
            for (guint i = 0; i < unused->len; ++i) {
                g_autofree char *full = flatpak_ref_format_ref(FLATPAK_REF(g_ptr_array_index(unused, i)));
                flatpak_transaction_add_uninstall(cleanup, full, nullptr);
            }
            runTransaction(cleanup, QStringLiteral("Убираю"), progress, cancellable);
        }
    }
    return failure;
}

QString update(const QStringList &refs, const Progress &progress, GCancellable *cancellable)
{
    ContextScope scope;
    QString failure;
    QString error;
    const QList<Update> pending = updates(&error, cancellable);
    if (!error.isEmpty())
        return error;
    for (const bool user : {true, false}) {
        g_autoptr(GError) gerror = nullptr;
        g_autoptr(FlatpakInstallation) installation = user ? userInstallation(&gerror) : flatpak_installation_new_system(cancellable, &gerror);
        if (!installation)
            continue;
        g_autoptr(FlatpakTransaction) transaction = flatpak_transaction_new_for_installation(installation, cancellable, &gerror);
        if (!transaction)
            continue;
        int added = 0;
        for (const Update &u : pending) {
            if (u.user != user || (!refs.isEmpty() && !refs.contains(u.ref)))
                continue;
            if (flatpak_transaction_add_update(transaction, u.ref.toUtf8().constData(), nullptr, nullptr, nullptr))
                ++added;
        }
        if (added == 0)
            continue;
        const QString result = runTransaction(transaction, QStringLiteral("Обновляю"), progress, cancellable);
        if (!result.isEmpty())
            failure = result;
    }
    return failure;
}

QList<Update> updates(QString *error, GCancellable *cancellable)
{
    ContextScope scope;
    QList<Update> result;
    for (const bool user : {true, false}) {
        g_autoptr(GError) gerror = nullptr;
        g_autoptr(FlatpakInstallation) installation = user ? userInstallation(&gerror) : flatpak_installation_new_system(cancellable, &gerror);
        if (!installation)
            continue;
        g_autoptr(GPtrArray) refs = flatpak_installation_list_installed_refs_for_update(installation, cancellable, &gerror);
        if (!refs) {
            if (error && user)
                *error = describe(gerror);
            continue;
        }
        for (guint i = 0; i < refs->len; ++i) {
            auto *ref = FLATPAK_INSTALLED_REF(g_ptr_array_index(refs, i));
            g_autofree char *full = flatpak_ref_format_ref(FLATPAK_REF(ref));
            Update u;
            u.id = QString::fromUtf8(flatpak_ref_get_name(FLATPAK_REF(ref)));
            u.ref = QString::fromUtf8(full);
            u.name = QString::fromUtf8(flatpak_installed_ref_get_appdata_name(ref));
            u.user = user;
            result << u;
        }
    }
    return result;
}

} // namespace FlatpakOps
