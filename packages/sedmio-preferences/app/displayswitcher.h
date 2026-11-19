#pragma once

#include <KScreen/Config>

#include <QObject>
#include <QPointer>
#include <QTimer>
#include <QVariantList>

class QQuickWindow;

// Выбор режима экранов (Meta+P, подключили второй экран) вместо окна
// kscreen_osd_service из Plasma. kded (модуль kscreen) зовёт по D-Bus
// org.kde.kscreen.osdService.showActionSelector(); служба сама показывает
// выбор и сама применяет режим. Мы запускаемся вместо kscreen_osd_service
// (drop-in к plasma-kscreen-osd.service) и отвечаем по тому же интерфейсу.
// Режимы — как у KDE (kscreen/common/osdaction.cpp), для двух экранов.
class DisplaySwitcher : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.kde.kscreen.osdService")

    // [{action, title}] — action: "internal" | "clone" | "extend" | "external".
    Q_PROPERTY(QVariantList choices READ choices NOTIFY changed)
    // Режим, который сейчас на экранах (индекс в choices), -1 — другой.
    Q_PROPERTY(int current READ current NOTIFY changed)
    // Вместо выбора: «второй экран не подключён» и т. п.
    Q_PROPERTY(QString message READ message NOTIFY changed)
    // Ширина экрана, где покажем выбор (логические пиксели): плитки ужимаются.
    Q_PROPERTY(int screenWidth READ screenWidth NOTIFY changed)

public:
    explicit DisplaySwitcher(QObject *parent = nullptr);

    bool registerOnBus();
    void setWindow(QQuickWindow *window);

    QVariantList choices() const { return m_choices; }
    int current() const { return m_current; }
    QString message() const { return m_message; }
    int screenWidth() const { return m_screenWidth; }

    Q_INVOKABLE void choose(const QString &action);
    Q_INVOKABLE void openDisplaySettings();

public Q_SLOTS:
    Q_SCRIPTABLE void showActionSelector();
    Q_SCRIPTABLE void hideOsd();

Q_SIGNALS:
    void changed();
    // Ещё раз Meta+P при открытом выборе — к следующему варианту.
    void advance();

private:
    void update(const KScreen::ConfigPtr &config);
    void present();

    QPointer<QQuickWindow> m_window;
    KScreen::ConfigPtr m_config;
    QString m_screen; // где показать (имя выхода)
    QVariantList m_choices;
    int m_current = -1;
    QString m_message;
    int m_screenWidth = 1600;
    QTimer m_quitTimer;
};
