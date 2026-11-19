#include "sound.h"

#include <PulseAudioQt/Client>
#include <PulseAudioQt/Context>
#include <PulseAudioQt/Port>
#include <PulseAudioQt/Profile>
#include <PulseAudioQt/Server>

#include <pulse/context.h>
#include <pulse/stream.h>

#include <QFile>
#include <QIcon>
#include <QProcess>

using namespace PulseAudioQt;

namespace
{
// Монитор вывода (то, что играет) — не микрофон.
bool isMonitor(const Source *source)
{
    return source->properties().value(QStringLiteral("device.class")).toString() == QLatin1String("monitor")
        || source->name().endsWith(QLatin1String(".monitor"));
}

QString prop(const PulseObject *object, const char *key)
{
    return object->properties().value(QLatin1String(key)).toString();
}

// Звуки событий (щелчки, уведомления) мелькают на долю секунды — не программы.
bool isEventSound(const SinkInput *input)
{
    return prop(input, "media.role") == QLatin1String("event");
}

qreal fraction(qint64 volume)
{
    return qreal(volume) / qreal(normalVolume());
}

qint64 absolute(qreal fraction)
{
    return qBound<qint64>(minimumVolume(), qRound64(fraction * qreal(normalVolume())), maximumUIVolume());
}

QString iconOr(const QString &name, const QString &fallback)
{
    return !name.isEmpty() && QIcon::hasThemeIcon(name) ? name : fallback;
}

// Название устройства: у PipeWire это «карта + профиль» («Встроенное аудио
// Аналоговый стерео») — длинно и не влезает. Если у карты одно такое
// устройство, хватит названия карты; одинаковые названия — полностью.
QStringList deviceTitles(const QList<Device *> &devices, bool input)
{
    QHash<quint32, Card *> cards;
    for (Card *card : Context::instance()->cards())
        cards.insert(card->index(), card);
    QStringList titles;
    for (Device *device : devices) {
        QString title;
        if (Card *card = cards.value(device->cardIndex())) {
            int count = 0;
            if (input) {
                for (Source *source : card->sources())
                    count += isMonitor(source) ? 0 : 1;
            } else {
                count = card->sinks().size();
            }
            if (count == 1)
                title = prop(card, "device.description");
        }
        titles << (title.isEmpty() ? device->description() : title);
    }
    for (int i = 0; i < titles.size(); ++i) {
        if (titles.count(titles.at(i)) > 1) {
            for (int j = 0; j < titles.size(); ++j) {
                if (j != i && titles.at(j) == titles.at(i))
                    titles[j] = devices.at(j)->description();
            }
            titles[i] = devices.at(i)->description();
        }
    }
    return titles;
}
} // namespace

Sound::Sound(QObject *parent)
    : QObject(parent)
{
    // Сервер шлёт изменения пачками (по каналам, по объектам) — пересчитываем
    // всё разом, чуть позже.
    m_refresh.setSingleShot(true);
    m_refresh.setInterval(30);
    connect(&m_refresh, &QTimer::timeout, this, &Sound::refresh);

    Context::setApplicationId(QStringLiteral("org.sedmio.Preferences"));
    Context *context = Context::instance();
    connect(context, &Context::stateChanged, this, &Sound::schedule);
    connect(context, &Context::sinkAdded, this, [this](Sink *o) { watch(o); });
    connect(context, &Context::sourceAdded, this, [this](Source *o) { watch(o); });
    connect(context, &Context::sinkInputAdded, this, [this](SinkInput *o) { watch(o); });
    connect(context, &Context::cardAdded, this, [this](Card *o) { watch(o); });
    connect(context, &Context::sinkRemoved, this, &Sound::schedule);
    connect(context, &Context::sourceRemoved, this, &Sound::schedule);
    connect(context, &Context::sinkInputRemoved, this, &Sound::schedule);
    connect(context, &Context::cardRemoved, this, &Sound::schedule);
    connect(context, &Context::clientAdded, this, &Sound::schedule);
    connect(context->server(), &Server::defaultSinkChanged, this, &Sound::schedule);
    connect(context->server(), &Server::defaultSourceChanged, this, &Sound::schedule);
    connect(context->server(), &Server::updated, this, &Sound::schedule);

    for (Sink *o : context->sinks())
        watch(o);
    for (Source *o : context->sources())
        watch(o);
    for (SinkInput *o : context->sinkInputs())
        watch(o);
    for (Card *o : context->cards())
        watch(o);
    refresh();
}

Sound::~Sound()
{
    stopMeter();
}

void Sound::watch(QObject *object)
{
    // Любое изменение объекта — пересчитать. Сигналы у PulseAudioQt
    // по каждому свойству; подписываемся на все *Changed разом.
    const QMetaObject *meta = object->metaObject();
    const QMetaMethod slot = metaObject()->method(metaObject()->indexOfSlot("schedule()"));
    for (int i = 0; i < meta->methodCount(); ++i) {
        const QMetaMethod method = meta->method(i);
        if (method.methodType() == QMetaMethod::Signal && method.parameterCount() == 0 && method.name().endsWith("Changed"))
            connect(object, method, this, slot, Qt::UniqueConnection);
    }
    schedule();
}

void Sound::schedule()
{
    if (!m_refresh.isActive())
        m_refresh.start();
}

QVariantMap Sound::describe(const QList<Device *> &devices, Device *current, bool input, QList<quint32> &portMap) const
{
    const QStringList titles = deviceTitles(devices, input);
    const int index = devices.indexOf(current);

    // Разъёмы: только те, куда что-то подключено (или неизвестно), и
    // нынешний — даже если «отключён».
    QStringList ports;
    int port = -1;
    portMap.clear();
    if (current) {
        const QList<Port *> all = current->ports();
        for (int i = 0; i < all.size(); ++i) {
            const bool active = quint32(i) == current->activePortIndex();
            if (all.at(i)->availability() == Port::Unavailable && !active)
                continue;
            if (active)
                port = ports.size();
            ports << all.at(i)->description();
            portMap << quint32(i);
        }
    }

    return {
        {QStringLiteral("devices"), titles},
        {QStringLiteral("device"), index},
        {QStringLiteral("ports"), ports.size() > 1 ? ports : QStringList()},
        {QStringLiteral("port"), port},
        {QStringLiteral("volume"), current ? fraction(current->volume()) : 0.0},
        {QStringLiteral("muted"), current ? current->isMuted() : false},
        {QStringLiteral("writable"), current ? current->isVolumeWritable() : false},
    };
}

void Sound::refresh()
{
    Context *context = Context::instance();
    m_ready = context->state() == Context::State::Ready;

    m_sinks.clear();
    QList<Device *> sinks;
    for (Sink *sink : context->sinks()) {
        m_sinks << sink;
        sinks << sink;
    }
    m_sources.clear();
    QList<Device *> sources;
    for (Source *source : context->sources()) {
        if (isMonitor(source))
            continue;
        m_sources << source;
        sources << source;
    }
    m_output = describe(sinks, context->server()->defaultSink(), false, m_outputPorts);
    m_input = describe(sources, context->server()->defaultSource(), true, m_inputPorts);

    m_apps.clear();
    for (SinkInput *input : context->sinkInputs()) {
        if (input->isVirtualStream() || !input->hasVolume() || isEventSound(input))
            continue;
        const Client *client = input->client();
        QString title = prop(input, "application.name");
        if (title.isEmpty() && client)
            title = client->name();
        if (title.isEmpty())
            title = input->name();
        QString subtitle = input->name();
        if (subtitle == title || subtitle == QLatin1String("playback") || subtitle.startsWith(QLatin1String("audio stream")))
            subtitle.clear();
        QString icon = prop(input, "application.icon_name");
        if (icon.isEmpty() && client)
            icon = prop(client, "application.icon_name");
        if (icon.isEmpty())
            icon = prop(input, "application.process.binary");
        m_apps << QVariantMap{
            {QStringLiteral("id"), input->index()},
            {QStringLiteral("title"), title},
            {QStringLiteral("subtitle"), subtitle},
            {QStringLiteral("icon"), iconOr(icon, QStringLiteral("audio-volume-high"))},
            {QStringLiteral("volume"), fraction(input->volume())},
            {QStringLiteral("muted"), input->isMuted()},
        };
    }

    m_cards.clear();
    m_cardObjects.clear();
    m_cardProfiles.clear();
    for (Card *card : context->cards()) {
        QStringList titles;
        QList<quint32> map;
        int current = -1;
        const QList<Profile *> profiles = card->profiles();
        for (int i = 0; i < profiles.size(); ++i) {
            const bool active = quint32(i) == card->activeProfileIndex();
            if (profiles.at(i)->availability() == Profile::Unavailable && !active)
                continue;
            if (active)
                current = titles.size();
            titles << profiles.at(i)->description();
            map << quint32(i);
        }
        if (titles.size() < 2)
            continue;
        QString title = prop(card, "device.description");
        if (title.isEmpty())
            title = card->name();
        m_cards << QVariantMap{{QStringLiteral("title"), title}, {QStringLiteral("profiles"), titles}, {QStringLiteral("profile"), current}};
        m_cardObjects << card;
        m_cardProfiles << map;
    }

    Q_EMIT changed();
    startMeter();
}

Device *Sound::currentDevice(bool input) const
{
    Server *server = Context::instance()->server();
    return input ? static_cast<Device *>(server->defaultSource()) : static_cast<Device *>(server->defaultSink());
}

void Sound::selectDevice(bool input, int index)
{
    if (input) {
        if (index >= 0 && index < m_sources.size() && m_sources.at(index))
            m_sources.at(index)->setDefault(true);
    } else if (index >= 0 && index < m_sinks.size() && m_sinks.at(index)) {
        m_sinks.at(index)->setDefault(true);
    }
}

void Sound::selectPort(bool input, int index)
{
    const QList<quint32> &map = input ? m_inputPorts : m_outputPorts;
    if (Device *device = currentDevice(input); device && index >= 0 && index < map.size())
        device->setActivePortIndex(map.at(index));
}

void Sound::setVolume(bool input, qreal volume)
{
    Device *device = currentDevice(input);
    if (!device)
        return;
    device->setVolume(absolute(volume));
    // Подвинули громкость — значит, хотят слышать.
    if (device->isMuted() && volume > 0)
        device->setMuted(false);
}

void Sound::setMuted(bool input, bool muted)
{
    if (Device *device = currentDevice(input))
        device->setMuted(muted);
}

void Sound::setAppVolume(quint32 id, qreal volume)
{
    for (SinkInput *input : Context::instance()->sinkInputs()) {
        if (input->index() == id) {
            input->setVolume(absolute(volume));
            if (input->isMuted() && volume > 0)
                input->setMuted(false);
        }
    }
}

void Sound::setAppMuted(quint32 id, bool muted)
{
    for (SinkInput *input : Context::instance()->sinkInputs()) {
        if (input->index() == id)
            input->setMuted(muted);
    }
}

void Sound::selectProfile(int card, int profile)
{
    if (card < 0 || card >= m_cardObjects.size() || !m_cardObjects.at(card))
        return;
    const QList<quint32> &map = m_cardProfiles.at(card);
    if (profile >= 0 && profile < map.size())
        m_cardObjects.at(card)->setActiveProfileIndex(map.at(profile));
}

void Sound::testOutput()
{
    Sink *sink = Context::instance()->server()->defaultSink();
    if (!sink)
        return;
    // Звук темы freedesktop; нет его — колокольчик Ocean (KDE).
    QString file = QStringLiteral("/usr/share/sounds/freedesktop/stereo/audio-test-signal.oga");
    if (!QFile::exists(file))
        file = QStringLiteral("/usr/share/sounds/ocean/stereo/bell.oga");
    QProcess::startDetached(QStringLiteral("pw-play"), {QStringLiteral("--target"), sink->name(), file});
}

// Уровень микрофона — как в plasma-pa: запись с источника в 25 значений
// в секунду, сервер сам считает пик (PA_STREAM_PEAK_DETECT).
void Sound::setMetering(bool metering)
{
    if (metering == m_metering)
        return;
    m_metering = metering;
    Q_EMIT meteringChanged();
    if (metering)
        startMeter();
    else
        stopMeter();
}

void Sound::startMeter()
{
    Context *context = Context::instance();
    Source *source = context->server()->defaultSource();
    const quint32 index = m_metering && source && !isMonitor(source) ? source->index() : UINT32_MAX;
    if (index == m_meterSource && (m_meter || index == UINT32_MAX))
        return;
    stopMeter();
    m_meterSource = index;
    if (index == UINT32_MAX || !context->context() || pa_context_get_state(context->context()) != PA_CONTEXT_READY)
        return;

    pa_sample_spec spec;
    spec.format = PA_SAMPLE_FLOAT32NE;
    spec.rate = 25;
    spec.channels = 1;
    pa_proplist *props = pa_proplist_new();
    // Не показывать этот поток в списках программ, пишущих звук.
    pa_proplist_sets(props, PA_PROP_APPLICATION_ID, "org.PulseAudio.pavucontrol");
    pa_proplist_sets(props, PA_PROP_APPLICATION_NAME, "Sedmio Preferences");
    m_meter = pa_stream_new_with_proplist(context->context(), "Уровень микрофона", &spec, nullptr, props);
    pa_proplist_free(props);
    if (!m_meter)
        return;
    pa_stream_set_read_callback(m_meter, &Sound::onPeak, this);

    pa_buffer_attr attr{};
    attr.maxlength = UINT32_MAX;
    attr.fragsize = sizeof(float);
    const QByteArray device = QByteArray::number(index);
    const auto flags = pa_stream_flags_t(PA_STREAM_DONT_MOVE | PA_STREAM_PEAK_DETECT | PA_STREAM_ADJUST_LATENCY);
    if (pa_stream_connect_record(m_meter, device.constData(), &attr, flags) < 0) {
        pa_stream_unref(m_meter);
        m_meter = nullptr;
    }
}

void Sound::stopMeter()
{
    if (m_meter) {
        pa_stream_set_read_callback(m_meter, nullptr, nullptr);
        pa_stream_disconnect(m_meter);
        pa_stream_unref(m_meter);
        m_meter = nullptr;
    }
    m_meterSource = UINT32_MAX;
    if (m_level != 0) {
        m_level = 0;
        Q_EMIT levelChanged();
    }
}

void Sound::onPeak(pa_stream *stream, size_t, void *self)
{
    auto *sound = static_cast<Sound *>(self);
    float peak = -1;
    while (pa_stream_readable_size(stream) > 0) {
        const void *data = nullptr;
        size_t length = 0;
        if (pa_stream_peek(stream, &data, &length) < 0)
            return;
        if (!data && length == 0)
            break;
        if (data && length >= sizeof(float))
            peak = static_cast<const float *>(data)[length / sizeof(float) - 1];
        pa_stream_drop(stream);
    }
    if (peak < 0)
        return;
    const qreal level = qBound(0.0, qreal(peak), 1.0);
    if (!qFuzzyCompare(level + 1, sound->m_level + 1)) {
        sound->m_level = level;
        Q_EMIT sound->levelChanged();
    }
}
