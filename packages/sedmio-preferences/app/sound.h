#pragma once

#include <QObject>
#include <QPointer>
#include <QQmlEngine>
#include <QTimer>
#include <QVariantList>

#include <PulseAudioQt/Sink>
#include <PulseAudioQt/SinkInput>
#include <PulseAudioQt/Source>
#include <PulseAudioQt/Card>

struct pa_stream;

// «Звук»: устройства вывода и ввода, громкость, звук программ, профили
// звуковых карт. Через PulseAudio API (в Sedmio это pipewire-pulse) —
// библиотекой PulseAudioQt, как plasma-pa. Всё применяется сразу.
class Sound : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    // Связь со звуковым сервером есть (иначе — сообщение вместо разделов).
    Q_PROPERTY(bool ready READ ready NOTIFY changed)
    // Вывод и ввод одинаково: {devices: [названия], device: индекс,
    // ports: [названия разъёмов], port: индекс, volume: 0…1.5 (1 — 100 %),
    // muted, writable}.
    Q_PROPERTY(QVariantMap output READ output NOTIFY changed)
    Q_PROPERTY(QVariantMap input READ input NOTIFY changed)
    // Программы со звуком: [{id, title, subtitle, icon, volume, muted}].
    Q_PROPERTY(QVariantList apps READ apps NOTIFY changed)
    // Звуковые карты, у которых есть из чего выбрать:
    // [{title, profiles: [названия], profile: индекс}].
    Q_PROPERTY(QVariantList cards READ cards NOTIFY changed)
    // Уровень с микрофона по умолчанию, 0…1 — пока metering (окно
    // активно): иначе микрофон зря занят.
    Q_PROPERTY(qreal level READ level NOTIFY levelChanged)
    Q_PROPERTY(bool metering READ metering WRITE setMetering NOTIFY meteringChanged)

public:
    explicit Sound(QObject *parent = nullptr);
    ~Sound() override;

    bool ready() const { return m_ready; }
    QVariantMap output() const { return m_output; }
    QVariantMap input() const { return m_input; }
    QVariantList apps() const { return m_apps; }
    QVariantList cards() const { return m_cards; }
    qreal level() const { return m_level; }
    bool metering() const { return m_metering; }
    void setMetering(bool metering);

    Q_INVOKABLE void selectDevice(bool input, int index);
    Q_INVOKABLE void selectPort(bool input, int index);
    Q_INVOKABLE void setVolume(bool input, qreal volume);
    Q_INVOKABLE void setMuted(bool input, bool muted);
    Q_INVOKABLE void setAppVolume(quint32 id, qreal volume);
    Q_INVOKABLE void setAppMuted(quint32 id, bool muted);
    Q_INVOKABLE void selectProfile(int card, int profile);
    Q_INVOKABLE void testOutput();

Q_SIGNALS:
    void changed();
    void levelChanged();
    void meteringChanged();

private Q_SLOTS:
    void schedule();

private:
    void watch(QObject *object);
    void refresh();
    QVariantMap describe(const QList<PulseAudioQt::Device *> &devices, PulseAudioQt::Device *current, bool input, QList<quint32> &portMap) const;
    PulseAudioQt::Device *currentDevice(bool input) const;

    void startMeter();
    void stopMeter();
    static void onPeak(pa_stream *stream, size_t length, void *self);

    QTimer m_refresh;
    bool m_ready = false;
    QVariantMap m_output;
    QVariantMap m_input;
    QVariantList m_apps;
    QVariantList m_cards;

    QList<QPointer<PulseAudioQt::Sink>> m_sinks;
    QList<QPointer<PulseAudioQt::Source>> m_sources;
    QList<quint32> m_outputPorts; // позиция в списке → индекс разъёма устройства
    QList<quint32> m_inputPorts;
    QList<QPointer<PulseAudioQt::Card>> m_cardObjects;
    QList<QList<quint32>> m_cardProfiles; // позиция → индекс профиля карты

    pa_stream *m_meter = nullptr;
    quint32 m_meterSource = UINT32_MAX;
    qreal m_level = 0;
    bool m_metering = false;
};
