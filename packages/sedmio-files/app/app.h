#pragma once

#include <QDBusAbstractAdaptor>
#include <QObject>
#include <QPointer>
#include <QUrl>
#include <QWindow>
#include <QtQml/qqmlregistration.h>

class QQmlEngine;
class QJSEngine;

// Программа целиком: окна и служба org.freedesktop.FileManager1.
//
// Работает один процесс на сеанс. Повторный запуск (из меню, xdg-open,
// «Показать в папке» в браузере) не поднимает второй процесс, а просит
// уже работающий открыть ещё одно окно — так быстрее, и задания копирования
// со своими вопросами живут в одном месте.
class App : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    // Окно, в котором пользователь работал последним: туда — ошибки
    // и вопросы заданий.
    Q_PROPERTY(QWindow *lastWindow READ lastWindow NOTIFY lastWindowChanged)

public:
    explicit App(QQmlEngine *engine);
    ~App() override;

    static App *instance();
    static App *create(QQmlEngine *, QJSEngine *);

    // Занять имена на шине. false — «Файлы» уже запущены.
    bool registerOnBus();
    // Передать просьбу запущенному экземпляру: ShowFolders или ShowItems.
    static bool forward(const QString &method, const QStringList &uris);

    // Открыть окно с папкой; select — что в ней выделить.
    Q_INVOKABLE void openWindow(const QUrl &folder, const QList<QUrl> &select = {}, const QString &token = {});
    void showFolders(const QStringList &uris, const QString &token);
    void showItems(const QStringList &uris, const QString &token);

    QWindow *lastWindow() const { return m_lastWindow; }

    // Задание с файлами началось или кончилось: пока они идут, программа
    // не закрывается, даже если закрыли все окна.
    void jobStarted();
    void jobFinished();
    // Закрыться, если ни окон, ни заданий.
    void maybeQuit();

Q_SIGNALS:
    void lastWindowChanged();

private:
    QQmlEngine *m_engine;
    QList<QPointer<QWindow>> m_windows;
    QPointer<QWindow> m_lastWindow;
    int m_jobs = 0;
};

// org.freedesktop.FileManager1 — так другие программы просят показать
// папку или файл в файловом менеджере.
class FileManager1Adaptor : public QDBusAbstractAdaptor
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.freedesktop.FileManager1")

public:
    explicit FileManager1Adaptor(App *app);

public Q_SLOTS:
    void ShowFolders(const QStringList &uriList, const QString &startUpId);
    void ShowItems(const QStringList &uriList, const QString &startUpId);
    void ShowItemProperties(const QStringList &uriList, const QString &startUpId);

private:
    App *m_app;
};
