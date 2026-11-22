#pragma once

#include <QList>
#include <QString>
#include <QStringList>

#include <functional>

typedef struct _GCancellable GCancellable;

// Работа с Flatpak через libflatpak. Всё — синхронно: звать в своём потоке
// (функции сами заводят там свой GMainContext, чтобы прогресс не шёл через
// главный цикл программы). Ставим в установку пользователя: без пароля, и
// программа видна только ему.
namespace FlatpakOps
{

// Доля 0…1 (или -1 — неизвестно) и что сейчас делается, по-русски.
using Progress = std::function<void(double fraction, const QString &text)>;

// Flathub подключён у пользователя; нет — подключить из
// /usr/share/sedmio/store/flathub.flatpakrepo. Пусто — всё хорошо, иначе —
// ошибка для человека.
QString ensureFlathub();

// Каталог Flathub пользователя старше maxAgeSecs (или его нет) — скачать заново.
// changed — каталог обновился (его надо перечитать).
QString refreshAppstream(qint64 maxAgeSecs, bool *changed);

// Что будет при установке: сколько качать и занять (вместе со средами
// выполнения, которых ещё нет), какие среды доставятся, что программе
// разрешено. Сеть, до пары секунд.
struct Preview {
    bool ok = false;
    QString error;
    qint64 download = 0;
    qint64 installed = 0;
    QStringList runtimes;   // имена сред, которые поставятся вместе
    // [{text, risky}]: что программа может вне песочницы.
    QList<std::pair<QString, bool>> permissions;
};
Preview preview(const QString &origin, const QString &ref, GCancellable *cancellable);

// Действия. Пусто — получилось; иначе — что пошло не так, по-русски.
QString install(const QString &origin, const QString &ref, const Progress &progress, GCancellable *cancellable);
// deleteData — и ~/.var/app/<id> (настройки и файлы программы).
QString uninstall(const QString &ref, bool user, bool deleteData, const Progress &progress, GCancellable *cancellable);
// refs пусто — обновить всё, что можно.
QString update(const QStringList &refs, const Progress &progress, GCancellable *cancellable);

// Программы, для которых есть обновления (сеть).
struct Update {
    QString id;
    QString ref;
    QString name;
    bool user = true;
    qint64 download = 0;
};
QList<Update> updates(QString *error, GCancellable *cancellable);

} // namespace FlatpakOps
