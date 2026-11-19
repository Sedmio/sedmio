#pragma once

#include <QDBusAbstractAdaptor>
#include <QDBusArgument>
#include <QDBusContext>
#include <QDBusMessage>
#include <QDBusObjectPath>
#include <QObject>
#include <QPointer>
#include <QTimer>
#include <QVariantMap>

class QQmlEngine;
class QQuickWindow;
class QWindow;

// Окно выбора файлов для всех программ: служба xdg-desktop-portal
// org.freedesktop.impl.portal.FileChooser («Открыть», «Сохранить как»),
// а с ним и AppChooser («Открыть с помощью» — то же окно, что в «Файлах»).
// Её вызывают Firefox, Chromium и Electron, Telegram, а с
// PLASMA_INTEGRATION_USE_PORTAL=1 — и программы KDE/Qt вместо своего окна.
//
//   sedmio-files --portal   запускает шина по первой просьбе
//                           (org.freedesktop.impl.portal.desktop.sedmio)
//
// Отдельный процесс от «Файлов»: упадёт окно выбора — файловый менеджер
// и его задания живут дальше. Без окон минуту — процесс выходит.
// Нет пакета (и файла sedmio.portal) — xdg-desktop-portal берёт окно KDE
// (/etc/xdg/xdg-desktop-portal/kde-portals.conf: FileChooser=sedmio;kde).

namespace Portal
{
// (us): 0 — шаблон имени ("*.png"), 1 — тип ("image/png").
struct FilterRule {
    uint type = 0;
    QString pattern;
};
// (sa(us)): название и правила.
struct Filter {
    QString name;
    QList<FilterRule> rules;
};
// (ss): вариант выбора — или выбранное значение в ответе.
struct ChoiceItem {
    QString id;
    QString label;
};
// (ssa(ss)s): выбор под списком файлов (кодировка и т. п.); без вариантов —
// галочка ("true"/"false").
struct Choice {
    QString id;
    QString label;
    QList<ChoiceItem> items;
    QString initial;
};
} // namespace Portal

Q_DECLARE_METATYPE(Portal::FilterRule)
Q_DECLARE_METATYPE(Portal::Filter)
Q_DECLARE_METATYPE(Portal::ChoiceItem)
Q_DECLARE_METATYPE(Portal::Choice)

// Просьба, пока окно открыто: xdg-desktop-portal может её отменить (Close).
class PortalRequest : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.freedesktop.impl.portal.Request")

public:
    explicit PortalRequest(const QDBusObjectPath &handle, QObject *parent);
    ~PortalRequest() override;

public Q_SLOTS:
    Q_SCRIPTABLE void Close();

Q_SIGNALS:
    void closeRequested();

private:
    QString m_path;
};

class FileChooserPortal : public QObject, protected QDBusContext
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.freedesktop.impl.portal.FileChooser")

public:
    explicit FileChooserPortal(QQmlEngine *engine);

    // Занять имя на шине; false — уже занято (второй процесс не нужен).
    bool registerOnBus();

public Q_SLOTS:
    Q_SCRIPTABLE uint OpenFile(const QDBusObjectPath &handle, const QString &app_id, const QString &parent_window, const QString &title,
                               const QVariantMap &options, QVariantMap &results);
    Q_SCRIPTABLE uint SaveFile(const QDBusObjectPath &handle, const QString &app_id, const QString &parent_window, const QString &title,
                               const QVariantMap &options, QVariantMap &results);
    Q_SCRIPTABLE uint SaveFiles(const QDBusObjectPath &handle, const QString &app_id, const QString &parent_window, const QString &title,
                                const QVariantMap &options, QVariantMap &results);

private:
    // mode: open, save, saveFiles.
    void show(const QString &mode, const QDBusObjectPath &handle, const QString &parentWindow, const QString &title, const QVariantMap &options);
    // Своё окно не создалось — отдать просьбу окну KDE (тот же интерфейс)
    // и вернуть его ответ.
    void forwardToKde(const QDBusMessage &call, const QDBusObjectPath &handle);
    void windowsChanged();
    void idleQuit();

    friend class AppChooserPortal;
    void chooseApplication(const QDBusMessage &call, const QDBusObjectPath &handle, const QString &parentWindow, const QStringList &choices,
                           const QVariantMap &options);
    QWindow *promptWindow();

    QQmlEngine *m_engine;
    int m_open = 0;
    QTimer m_idle;
    QPointer<QWindow> m_promptWindow;
};

// org.freedesktop.impl.portal.AppChooser на том же объекте, что FileChooser.
class AppChooserPortal : public QDBusAbstractAdaptor
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.freedesktop.impl.portal.AppChooser")

public:
    explicit AppChooserPortal(FileChooserPortal *portal);

public Q_SLOTS:
    uint ChooseApplication(const QDBusObjectPath &handle, const QString &app_id, const QString &parent_window, const QStringList &choices,
                           const QVariantMap &options, const QDBusMessage &message, QVariantMap &results);
    // Список подходящих программ поменялся, пока окно открыто, — не обновляем:
    // в окне и так есть все программы.
    void UpdateChoices(const QDBusObjectPath &handle, const QStringList &choices);

private:
    FileChooserPortal *m_portal;
};
