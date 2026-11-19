#pragma once

#include <QObject>
#include <QVariantList>
#include <QtQml/qqmlregistration.h>

// Питание: когда гасить экран и засыпать, что делают кнопка питания и
// крышка. Сам демон — powerdevil (Plasma): он следит за бездействием,
// учитывает «не спать, пока идёт видео» и т. п. Мы пишем его powerdevilrc
// (группы [AC]/[Battery]/[LowBattery]) и просим перечитать.
class Power : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    // [{id: "AC"|"Battery", title, dim, off, sleep}] — секунды, 0 — никогда.
    // «От батареи» — только если батарея есть.
    Q_PROPERTY(QVariantList profiles READ profiles NOTIFY changed)
    // Значения PowerDevil::PowerButtonAction: 0 ничего, 1 сон, 8 выключить,
    // 16 спросить, 64 выключить экран.
    Q_PROPERTY(int powerButton READ powerButton NOTIFY changed)
    Q_PROPERTY(int lidAction READ lidAction NOTIFY changed)
    Q_PROPERTY(bool lidPresent READ lidPresent NOTIFY changed)
    Q_PROPERTY(bool canSuspend READ canSuspend NOTIFY changed)
    Q_PROPERTY(QString error READ error NOTIFY changed)

public:
    explicit Power(QObject *parent = nullptr);

    QVariantList profiles() const { return m_profiles; }
    int powerButton() const { return m_powerButton; }
    int lidAction() const { return m_lidAction; }
    bool lidPresent() const { return m_lidPresent; }
    bool canSuspend() const { return m_canSuspend; }
    QString error() const { return m_error; }

    // kind: "dim" | "off" | "sleep"; seconds: 0 — никогда.
    Q_INVOKABLE void setTimeout(const QString &profile, const QString &kind, int seconds);
    Q_INVOKABLE void setPowerButton(int action);
    Q_INVOKABLE void setLidAction(int action);

Q_SIGNALS:
    void changed();

private:
    void load();
    void notifyDaemon();

    bool m_isVM = false;
    bool m_canSuspend = false;
    bool m_hasBattery = false;
    bool m_lidPresent = false;
    QVariantList m_profiles;
    int m_powerButton = 16;
    int m_lidAction = 1;
    QString m_error;
};
