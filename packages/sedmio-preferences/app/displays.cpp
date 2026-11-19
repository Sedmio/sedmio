#include "displays.h"

#include <KScreen/ConfigMonitor>
#include <KScreen/EDID>
#include <KScreen/GetConfigOperation>
#include <KScreen/Mode>
#include <KScreen/Output>
#include <KScreen/SetConfigOperation>

#include <QLocale>

#include <algorithm>

namespace
{
constexpr int confirmSeconds = 15;

// Разрешения экрана — без повторов, от большего к меньшему.
QList<QSize> sizesOf(const KScreen::OutputPtr &output)
{
    QList<QSize> sizes;
    for (const auto &mode : output->modes()) {
        if (!sizes.contains(mode->size()))
            sizes.append(mode->size());
    }
    // Как в Windows: по ширине, при равной — по высоте.
    std::sort(sizes.begin(), sizes.end(), [](const QSize &a, const QSize &b) {
        return a.width() > b.width() || (a.width() == b.width() && a.height() > b.height());
    });
    return sizes;
}

// Частоты для разрешения — без повторов (59,94 и 60 разные), от большей.
QList<KScreen::ModePtr> ratesOf(const KScreen::OutputPtr &output, const QSize &size)
{
    QList<KScreen::ModePtr> modes;
    for (const auto &mode : output->modes()) {
        if (mode->size() != size)
            continue;
        const bool seen = std::any_of(modes.cbegin(), modes.cend(), [&](const KScreen::ModePtr &m) {
            return qAbs(m->refreshRate() - mode->refreshRate()) < 0.01;
        });
        if (!seen)
            modes.append(mode);
    }
    std::sort(modes.begin(), modes.end(), [](const KScreen::ModePtr &a, const KScreen::ModePtr &b) {
        return a->refreshRate() > b->refreshRate();
    });
    return modes;
}

QString rateLabel(float rate)
{
    const float rounded = qRound(rate);
    if (qAbs(rate - rounded) < 0.05)
        return QStringLiteral("%1 Гц").arg(int(rounded));
    return QStringLiteral("%1 Гц").arg(QLocale().toString(rate, 'f', 2));
}

int rotationIndex(KScreen::Output::Rotation rotation)
{
    switch (rotation) {
    case KScreen::Output::Left:
        return 1;
    case KScreen::Output::Inverted:
        return 2;
    case KScreen::Output::Right:
        return 3;
    default:
        return 0;
    }
}

KScreen::Output::Rotation rotationFromIndex(int index)
{
    switch (index) {
    case 1:
        return KScreen::Output::Left;
    case 2:
        return KScreen::Output::Inverted;
    case 3:
        return KScreen::Output::Right;
    default:
        return KScreen::Output::None;
    }
}

QString titleOf(const KScreen::OutputPtr &output)
{
    if (output->type() == KScreen::Output::Panel)
        return QStringLiteral("Встроенный экран");
    if (const auto *edid = output->edid(); edid && edid->isValid()) {
        const QString name = edid->name().trimmed();
        const QString vendor = edid->vendor().trimmed();
        if (!name.isEmpty())
            return name.startsWith(vendor, Qt::CaseInsensitive) || vendor.isEmpty() ? name : vendor + QLatin1Char(' ') + name;
    }
    return output->name();
}

QList<KScreen::OutputPtr> connected(const KScreen::ConfigPtr &config)
{
    QList<KScreen::OutputPtr> list;
    for (const auto &output : config->outputs()) {
        if (output->isConnected())
            list.append(output);
    }
    return list;
}

// Включённые экраны слева направо.
QList<KScreen::OutputPtr> enabledRow(const KScreen::ConfigPtr &config)
{
    QList<KScreen::OutputPtr> row;
    for (const auto &output : connected(config)) {
        if (output->isEnabled())
            row.append(output);
    }
    std::sort(row.begin(), row.end(), [](const KScreen::OutputPtr &a, const KScreen::OutputPtr &b) {
        return a->pos().x() < b->pos().x() || (a->pos().x() == b->pos().x() && a->id() < b->id());
    });
    return row;
}
} // namespace

Displays::Displays(QObject *parent)
    : QObject(parent)
{
    m_countdown.setInterval(1000);
    connect(&m_countdown, &QTimer::timeout, this, [this] {
        if (--m_revertIn <= 0) {
            revert();
            return;
        }
        Q_EMIT revertInChanged();
    });
    load();
}

Displays::~Displays()
{
    // Закрыли, не подтвердив, — вернуть прежнее (и дождаться: после нас
    // никто этого не сделает).
    if (m_revertIn > 0 && m_previous) {
        auto *operation = new KScreen::SetConfigOperation(m_previous);
        operation->exec();
    }
}

void Displays::load()
{
    auto *operation = new KScreen::GetConfigOperation();
    connect(operation, &KScreen::ConfigOperation::finished, this, [this](KScreen::ConfigOperation *op) {
        if (op->hasError()) {
            m_error = QStringLiteral("Не удалось узнать параметры экранов: %1").arg(op->errorString());
            Q_EMIT changed();
            return;
        }
        setConfig(qobject_cast<KScreen::GetConfigOperation *>(op)->config());
    });
}

void Displays::setConfig(const KScreen::ConfigPtr &config)
{
    m_current = config;
    KScreen::ConfigMonitor::instance()->addConfig(m_current);
    connect(KScreen::ConfigMonitor::instance(), &KScreen::ConfigMonitor::configurationChanged, this,
            &Displays::onConfigChanged, Qt::UniqueConnection);
    m_draft = m_current->clone();
    m_dirty = false;
    Q_EMIT changed();
}

// KWin сменил параметры (мы применили, подключили монитор…).
void Displays::onConfigChanged()
{
    if (m_dirty)
        return; // правки пользователя не затираем
    m_draft = m_current->clone();
    Q_EMIT changed();
}

QVariantList Displays::outputs() const
{
    QVariantList list;
    if (!m_draft)
        return list;

    auto outputs = connected(m_draft);
    std::sort(outputs.begin(), outputs.end(), [](const KScreen::OutputPtr &a, const KScreen::OutputPtr &b) {
        if (a->isEnabled() != b->isEnabled())
            return a->isEnabled();
        return a->pos().x() < b->pos().x() || (a->pos().x() == b->pos().x() && a->id() < b->id());
    });

    for (const auto &output : outputs) {
        const auto mode = output->currentMode() ? output->currentMode() : output->preferredMode();
        const auto preferred = output->preferredMode();
        const QSize size = mode ? mode->size() : QSize();

        QVariantList resolutions;
        int resolution = -1;
        const auto sizes = sizesOf(output);
        for (int i = 0; i < sizes.size(); ++i) {
            QString label = QStringLiteral("%1 × %2").arg(sizes[i].width()).arg(sizes[i].height());
            if (preferred && preferred->size() == sizes[i])
                label += QStringLiteral(" (рекомендуется)");
            resolutions.append(QVariantMap{{QStringLiteral("width"), sizes[i].width()},
                                           {QStringLiteral("height"), sizes[i].height()},
                                           {QStringLiteral("label"), label}});
            if (sizes[i] == size)
                resolution = i;
        }

        QVariantList rates;
        int rate = -1;
        const auto modes = ratesOf(output, size);
        for (int i = 0; i < modes.size(); ++i) {
            rates.append(QVariantMap{{QStringLiteral("rate"), modes[i]->refreshRate()},
                                     {QStringLiteral("label"), rateLabel(modes[i]->refreshRate())}});
            if (mode && qAbs(modes[i]->refreshRate() - mode->refreshRate()) < 0.01)
                rate = i;
        }

        const QSize logical = output->isEnabled() ? m_draft->logicalSizeForOutputInt(*output) : size;
        list.append(QVariantMap{
            {QStringLiteral("id"), output->id()},
            {QStringLiteral("title"), titleOf(output)},
            {QStringLiteral("connector"), output->name()},
            {QStringLiteral("builtin"), output->type() == KScreen::Output::Panel},
            {QStringLiteral("enabled"), output->isEnabled()},
            {QStringLiteral("primary"), output->isEnabled() && output->priority() == 1},
            {QStringLiteral("x"), output->pos().x()},
            {QStringLiteral("y"), output->pos().y()},
            {QStringLiteral("width"), logical.width()},
            {QStringLiteral("height"), logical.height()},
            {QStringLiteral("resolutions"), resolutions},
            {QStringLiteral("resolution"), resolution},
            {QStringLiteral("rates"), rates},
            {QStringLiteral("rate"), rate},
            {QStringLiteral("scale"), output->scale()},
            {QStringLiteral("rotation"), rotationIndex(output->rotation())},
        });
    }
    return list;
}

void Displays::setResolution(int outputId, int index)
{
    const auto output = m_draft ? m_draft->output(outputId) : KScreen::OutputPtr();
    if (!output)
        return;
    const auto sizes = sizesOf(output);
    if (index < 0 || index >= sizes.size())
        return;
    const auto modes = ratesOf(output, sizes[index]);
    if (modes.isEmpty())
        return;

    // Частоту оставляем прежней, если она есть и у нового разрешения.
    KScreen::ModePtr chosen = modes.first();
    if (const auto current = output->currentMode()) {
        for (const auto &mode : modes) {
            if (qAbs(mode->refreshRate() - current->refreshRate()) < 0.5) {
                chosen = mode;
                break;
            }
        }
    }
    output->setCurrentModeId(chosen->id());
    edited();
}

void Displays::setRate(int outputId, int index)
{
    const auto output = m_draft ? m_draft->output(outputId) : KScreen::OutputPtr();
    if (!output || !output->currentMode())
        return;
    const auto modes = ratesOf(output, output->currentMode()->size());
    if (index < 0 || index >= modes.size())
        return;
    output->setCurrentModeId(modes[index]->id());
    edited();
}

void Displays::setScale(int outputId, double scale)
{
    const auto output = m_draft ? m_draft->output(outputId) : KScreen::OutputPtr();
    if (!output || scale < 0.5 || scale > 3)
        return;
    output->setScale(scale);
    edited();
}

void Displays::setRotation(int outputId, int rotation)
{
    const auto output = m_draft ? m_draft->output(outputId) : KScreen::OutputPtr();
    if (!output)
        return;
    output->setRotation(rotationFromIndex(rotation));
    edited();
}

void Displays::setEnabled(int outputId, bool enabled)
{
    const auto output = m_draft ? m_draft->output(outputId) : KScreen::OutputPtr();
    if (!output || output->isEnabled() == enabled)
        return;

    if (!enabled) {
        // Последний включённый экран не выключаем — иначе картинки не будет вовсе.
        if (enabledRow(m_draft).size() <= 1)
            return;
        const bool wasPrimary = output->priority() == 1;
        output->setEnabled(false);
        if (wasPrimary)
            m_draft->setOutputPriority(enabledRow(m_draft).first(), 1);
    } else {
        if (!output->currentMode() && output->preferredMode())
            output->setCurrentModeId(output->preferredModeId());
        // Новый экран — справа от остальных.
        const auto row = enabledRow(m_draft);
        if (!row.isEmpty()) {
            const auto &last = row.last();
            output->setPos(QPoint(last->pos().x() + m_draft->logicalSizeForOutputInt(*last).width() + 1, 0));
        }
        output->setEnabled(true);
    }
    m_draft->adjustPriorities();
    edited();
}

void Displays::setPrimary(int outputId)
{
    const auto output = m_draft ? m_draft->output(outputId) : KScreen::OutputPtr();
    if (!output || !output->isEnabled())
        return;
    m_draft->setOutputPriority(output, 1);
    edited();
}

void Displays::move(int outputId, int step)
{
    if (!m_draft)
        return;
    auto row = enabledRow(m_draft);
    const auto it = std::find_if(row.begin(), row.end(), [&](const KScreen::OutputPtr &o) { return o->id() == outputId; });
    if (it == row.end())
        return;
    const int from = int(it - row.begin());
    const int to = from + step;
    if (to < 0 || to >= row.size())
        return;
    row.swapItemsAt(from, to);
    // Расставляем в новом порядке: x — по порядку, дальше layoutRow.
    int x = 0;
    for (const auto &output : row) {
        output->setPos(QPoint(x, 0));
        x += m_draft->logicalSizeForOutputInt(*output).width();
    }
    edited();
}

// Экраны встык в ряд, слева направо в прежнем порядке: после смены
// разрешения, масштаба или поворота не остаётся ни щелей, ни наложений.
void Displays::layoutRow()
{
    int x = 0;
    for (const auto &output : enabledRow(m_draft)) {
        output->setPos(QPoint(x, 0));
        x += m_draft->logicalSizeForOutputInt(*output).width();
    }
}

void Displays::edited()
{
    layoutRow();
    m_dirty = true;
    m_error.clear();
    Q_EMIT changed();
}

void Displays::send(const KScreen::ConfigPtr &config)
{
    if (!KScreen::Config::canBeApplied(config)) {
        m_error = QStringLiteral("Такие параметры экранов применить нельзя.");
        Q_EMIT changed();
        return;
    }
    auto *operation = new KScreen::SetConfigOperation(config);
    connect(operation, &KScreen::ConfigOperation::finished, this, [this](KScreen::ConfigOperation *op) {
        if (op->hasError()) {
            m_error = QStringLiteral("Не удалось применить: %1").arg(op->errorString());
            Q_EMIT changed();
        }
    });
}

void Displays::apply()
{
    if (!m_draft || !m_current || !m_dirty)
        return;
    if (!KScreen::Config::canBeApplied(m_draft)) {
        m_error = QStringLiteral("Такие параметры экранов применить нельзя.");
        Q_EMIT changed();
        return;
    }
    m_previous = m_current->clone();
    m_dirty = false;
    send(m_draft->clone());
    m_revertIn = confirmSeconds;
    m_countdown.start();
    Q_EMIT revertInChanged();
    Q_EMIT changed();
}

void Displays::confirm()
{
    m_countdown.stop();
    m_previous.reset();
    m_revertIn = 0;
    Q_EMIT revertInChanged();
}

void Displays::revert()
{
    m_countdown.stop();
    m_revertIn = 0;
    if (m_previous) {
        send(m_previous);
        m_previous.reset();
    }
    m_dirty = false;
    Q_EMIT revertInChanged();
    Q_EMIT changed();
}

void Displays::discard()
{
    if (!m_current)
        return;
    m_draft = m_current->clone();
    m_dirty = false;
    m_error.clear();
    Q_EMIT changed();
}
