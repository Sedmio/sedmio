#include "displayswitcher.h"

#include <KScreen/EDID>
#include <KScreen/GetConfigOperation>
#include <KScreen/Mode>
#include <KScreen/Output>
#include <KScreen/SetConfigOperation>

#include <LayerShellQt/Window>

#include <QCoreApplication>
#include <QDBusConnection>
#include <QProcess>
#include <QGuiApplication>
#include <QQuickWindow>
#include <QScreen>

namespace
{
// Первый — встроенный экран ноутбука, иначе по имени разъёма (DP-1 раньше
// HDMI-A-1): порядок не должен зависеть от того, какой экран сейчас
// основной, иначе после «Только второй» подписи менялись бы местами.
std::pair<KScreen::OutputPtr, KScreen::OutputPtr> splitOutputs(const KScreen::ConfigPtr &config)
{
    QList<KScreen::OutputPtr> outputs = config->connectedOutputs().values();
    if (outputs.size() != 2)
        return {};
    std::sort(outputs.begin(), outputs.end(), [](const KScreen::OutputPtr &a, const KScreen::OutputPtr &b) {
        const bool aPanel = a->type() == KScreen::Output::Panel;
        const bool bPanel = b->type() == KScreen::Output::Panel;
        if (aPanel != bPanel)
            return aPanel;
        return a->name() < b->name();
    });
    return {outputs.at(0), outputs.at(1)};
}

// Название монитора из EDID, иначе разъём.
QString nameOf(const KScreen::OutputPtr &output)
{
    if (const auto *edid = output->edid(); edid && edid->isValid() && !edid->name().trimmed().isEmpty())
        return edid->name().trimmed();
    return output->name();
}

// Экран был выключен — дать ему режим: предпочтительный, иначе самый большой.
void ensureMode(const KScreen::OutputPtr &output)
{
    if (output->currentMode())
        return;
    QString id = output->preferredModeId();
    if (id.isEmpty() || !output->mode(id)) {
        KScreen::ModePtr best;
        const auto modes = output->modes();
        for (const auto &mode : modes) {
            if (!best || mode->size().width() * mode->size().height() > best->size().width() * best->size().height()
                || (mode->size() == best->size() && mode->refreshRate() > best->refreshRate()))
                best = mode;
        }
        if (!best)
            return;
        id = best->id();
    }
    output->setCurrentModeId(id);
}
} // namespace

DisplaySwitcher::DisplaySwitcher(QObject *parent)
    : QObject(parent)
{
    // Как kscreen_osd_service: не нужен минуту — выходим, kded поднимет снова.
    m_quitTimer.setInterval(60000);
    m_quitTimer.setSingleShot(true);
    connect(&m_quitTimer, &QTimer::timeout, qApp, &QCoreApplication::quit);
    m_quitTimer.start();
}

bool DisplaySwitcher::registerOnBus()
{
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.registerObject(QStringLiteral("/org/kde/kscreen/osdService"), this, QDBusConnection::ExportScriptableSlots))
        return false;
    return bus.registerService(QStringLiteral("org.kde.kscreen.osdService"));
}

void DisplaySwitcher::setWindow(QQuickWindow *window)
{
    m_window = window;
    if (!window)
        return;
    // Поверх всего, по центру экрана, где работают; клавиатура — когда
    // окно активно (стрелки, Enter, Esc).
    auto *layer = LayerShellQt::Window::get(window);
    layer->setScope(QStringLiteral("on-screen-display"));
    layer->setLayer(LayerShellQt::Window::LayerOverlay);
    layer->setAnchors({});
    layer->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityOnDemand);
    connect(window, &QWindow::activeChanged, this, [this] {
        // Щёлкнули мимо — выбор больше не нужен.
        if (m_window && m_window->isVisible() && !m_window->isActive() && m_window->property("wasActive").toBool())
            hideOsd();
        if (m_window && m_window->isActive())
            m_window->setProperty("wasActive", true);
    });
}

void DisplaySwitcher::showActionSelector()
{
    m_quitTimer.stop();
    if (m_window && m_window->isVisible()) {
        Q_EMIT advance();
        return;
    }
    auto *operation = new KScreen::GetConfigOperation();
    connect(operation, &KScreen::ConfigOperation::finished, this, [this](KScreen::ConfigOperation *op) {
        if (op->hasError()) {
            qWarning() << "display switcher:" << op->errorString();
            m_quitTimer.start();
            return;
        }
        update(qobject_cast<KScreen::GetConfigOperation *>(op)->config());
        present();
    });
}

void DisplaySwitcher::update(const KScreen::ConfigPtr &config)
{
    m_config = config;
    m_screen.clear();
    m_choices.clear();
    m_current = -1;
    m_message.clear();

    const int count = config->connectedOutputs().size();
    if (count < 2) {
        m_message = QStringLiteral("Второй экран не подключён.");
    } else if (count > 2) {
        m_message = QStringLiteral("Подключено больше двух экранов — расставьте их в параметрах экрана.");
    } else {
        const auto [first, second] = splitOutputs(config);
        // Показываем на основном включённом экране (как kscreen), а не на
        // только что подключённом.
        const bool firstMain = first->isEnabled() && (first->type() == KScreen::Output::Panel || first->priority() == 1 || !second->isEnabled());
        m_screen = firstMain ? first->name() : second->name();
        const bool laptop = first->type() == KScreen::Output::Panel;
        auto add = [this](const QString &action, const QString &title) {
            m_choices.append(QVariantMap{{QStringLiteral("action"), action}, {QStringLiteral("title"), title}});
        };
        // У ноутбука ясно, какой экран какой; у двух мониторов — по названию
        // (одинаковые — ещё и по разъёму).
        QString firstName = nameOf(first);
        QString secondName = nameOf(second);
        if (firstName == secondName) {
            firstName += QStringLiteral(" (%1)").arg(first->name());
            secondName += QStringLiteral(" (%1)").arg(second->name());
        }
        add(QStringLiteral("internal"), laptop ? QStringLiteral("Только экран ноутбука") : QStringLiteral("Только %1").arg(firstName));
        add(QStringLiteral("clone"), QStringLiteral("Повторять"));
        add(QStringLiteral("extend"), QStringLiteral("Расширить"));
        add(QStringLiteral("external"), laptop ? QStringLiteral("Только внешний экран") : QStringLiteral("Только %1").arg(secondName));

        const bool firstOn = first->isEnabled();
        const bool secondOn = second->isEnabled();
        if (firstOn && secondOn)
            m_current = (first->replicationSource() != 0 || second->replicationSource() != 0) ? 1 : 2;
        else if (firstOn)
            m_current = 0;
        else if (secondOn)
            m_current = 3;
    }
    Q_EMIT changed();
}

void DisplaySwitcher::present()
{
    if (!m_window)
        return;
    m_window->setProperty("wasActive", false);
    QScreen *target = nullptr;
    const auto screens = QGuiApplication::screens();
    for (QScreen *screen : screens) {
        if (screen->name() == m_screen)
            target = screen;
    }
    auto *layer = LayerShellQt::Window::get(m_window);
    const int width = (target ? target : QGuiApplication::primaryScreen())->geometry().width();
    if (width != m_screenWidth) {
        m_screenWidth = width;
        Q_EMIT changed();
    }
    if (target) {
        layer->setScreen(target);
        m_window->setScreen(target);
    } else {
        layer->setWantsToBeOnActiveScreen(true);
    }
    m_window->show();
    m_window->requestActivate();
}

void DisplaySwitcher::hideOsd()
{
    if (m_window)
        m_window->hide();
    m_quitTimer.start();
}

void DisplaySwitcher::choose(const QString &action)
{
    if (!m_config) {
        hideOsd();
        return;
    }
    const KScreen::ConfigPtr copy = m_config->clone();
    const auto [first, second] = splitOutputs(copy);
    if (!first || !second) {
        hideOsd();
        return;
    }
    first->setReplicationSource(0);
    second->setReplicationSource(0);

    if (action == QLatin1String("internal")) {
        first->setEnabled(true);
        ensureMode(first);
        first->setPos({});
        second->setEnabled(false);
    } else if (action == QLatin1String("external")) {
        second->setEnabled(true);
        ensureMode(second);
        second->setPos({});
        first->setEnabled(false);
    } else if (action == QLatin1String("clone")) {
        first->setEnabled(true);
        second->setEnabled(true);
        ensureMode(first);
        ensureMode(second);
        // На Wayland режимы подбирает KWin, нам — только источник картинки.
        second->setReplicationSource(first->id());
    } else if (action == QLatin1String("extend")) {
        first->setEnabled(true);
        second->setEnabled(true);
        ensureMode(first);
        ensureMode(second);
        first->setPos({});
        second->setPos({copy->logicalSizeForOutputInt(*first).width(), 0});
    } else {
        hideOsd();
        return;
    }

    hideOsd();
    auto *operation = new KScreen::SetConfigOperation(copy);
    connect(operation, &KScreen::ConfigOperation::finished, this, [](KScreen::ConfigOperation *op) {
        if (op->hasError())
            qWarning() << "display switcher:" << op->errorString();
    });
}

void DisplaySwitcher::openDisplaySettings()
{
    QProcess::startDetached(QStringLiteral("sedmio-preferences"), {QStringLiteral("display")});
    hideOsd();
}
