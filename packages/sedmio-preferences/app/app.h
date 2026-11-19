#pragma once

#include <QDBusAbstractAdaptor>
#include <QObject>
#include <QPointer>
#include <QQuickWindow>

// Один процесс «Параметров» на сеанс (имя org.sedmio.Preferences): второй
// запуск передаёт ему раздел и выходит. Раздел — первый аргумент:
// display, wallpaper, mouse, keyboard, defaults, datetime, about.
class App : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString page READ page WRITE setPage NOTIFY pageChanged)

public:
    explicit App(QObject *parent = nullptr);

    QString page() const { return m_page; }
    void setPage(const QString &page);
    void setWindow(QQuickWindow *window) { m_window = window; }

    // Заняли имя на шине — мы первые.
    bool registerOnBus();
    // Передать раздел запущенному процессу. false — не ответил.
    static bool forward(const QString &page);

    static QString normalizePage(const QString &page);

    // Открыть раздел KDE, которого у нас пока нет (запасной путь).
    Q_INVOKABLE void openKde(const QString &module = QString());

public Q_SLOTS:
    void show(const QString &page, const QString &token);

Q_SIGNALS:
    void pageChanged();

private:
    QString m_page = QStringLiteral("display");
    QPointer<QQuickWindow> m_window;
};

class PreferencesAdaptor : public QDBusAbstractAdaptor
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.sedmio.Preferences")

public:
    explicit PreferencesAdaptor(App *app)
        : QDBusAbstractAdaptor(app)
        , m_app(app)
    {
    }

public Q_SLOTS:
    void Show(const QString &page, const QString &token) { m_app->show(page, token); }

private:
    App *m_app;
};
