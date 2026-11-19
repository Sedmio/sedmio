#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QTimer>

// Ночная подсветка (тёплые цвета вечером) — её делает KWin. Включение,
// режим и теплота — kwinrc [NightColor]; когда вечер — служба knighttimed
// (knighttimerc). Оба следят за своими файлами (KConfigWatcher), поэтому
// пишем с флагом Notify — применяется сразу. Состояние и предпросмотр —
// D-Bus org.kde.KWin.NightLight.
//
// «От заката до рассвета» — по координатам часового пояса
// (/usr/share/zoneinfo/zone1970.tab), а не по геолокации: без лишних
// служб и без отправки местоположения в сеть.
class NightLight : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(bool available READ available NOTIFY changed)
    Q_PROPERTY(bool enabled READ enabled NOTIFY changed)
    // "sunset" | "times" | "always"
    Q_PROPERTY(QString mode READ mode NOTIFY changed)
    // Ночная теплота, К (меньше — теплее).
    Q_PROPERTY(int temperature READ temperature NOTIFY changed)
    // Расписание «По расписанию», "ЧЧ:ММ".
    Q_PROPERTY(QString evening READ evening NOTIFY changed)
    Q_PROPERTY(QString morning READ morning NOTIFY changed)
    // Город часового пояса для «от заката до рассвета» (пусто — не знаем).
    Q_PROPERTY(QString place READ place NOTIFY changed)
    // Что сейчас: «Сейчас включена, выключится в 07:12» и т. п.
    Q_PROPERTY(QString status READ status NOTIFY changed)

public:
    explicit NightLight(QObject *parent = nullptr);
    ~NightLight() override;

    bool available() const { return m_available; }
    bool enabled() const { return m_enabled; }
    QString mode() const { return m_mode; }
    int temperature() const { return m_temperature; }
    QString evening() const { return m_evening; }
    QString morning() const { return m_morning; }
    QString place() const { return m_place; }
    QString status() const { return m_status; }

    Q_INVOKABLE void setEnabled(bool enabled);
    Q_INVOKABLE void setMode(const QString &mode);
    Q_INVOKABLE void setTemperature(int kelvin);
    Q_INVOKABLE void setTimes(const QString &evening, const QString &morning);
    Q_INVOKABLE void preview(int kelvin);
    Q_INVOKABLE void stopPreview();

Q_SIGNALS:
    void changed();

private Q_SLOTS:
    void readState();

private:
    void readConfig();
    bool zoneLocation(double *latitude, double *longitude);

    bool m_available = false;
    bool m_enabled = false;
    QString m_mode = QStringLiteral("sunset");
    int m_temperature = 4500;
    QString m_evening = QStringLiteral("21:00");
    QString m_morning = QStringLiteral("07:00");
    QString m_place;
    QString m_status;
    bool m_previewing = false;
    QTimer m_poll;
};
