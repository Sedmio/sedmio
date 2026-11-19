#include "keyboard.h"

#include <KConfig>
#include <KConfigGroup>

#include <QCollator>
#include <QDBusArgument>
#include <QDBusMetaType>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QHash>

#include <xkbcommon/xkbregistry.h>

#include <libintl.h>

#include <algorithm>
#include <optional>

namespace
{
// Переключение — параметр xkb из группы grp:.
const QHash<QString, QString> switchOptions = {
    {QStringLiteral("alt_shift"), QStringLiteral("grp:alt_shift_toggle")},
    {QStringLiteral("ctrl_shift"), QStringLiteral("grp:ctrl_shift_toggle")},
    {QStringLiteral("win_space"), QStringLiteral("grp:win_space_toggle")},
    {QStringLiteral("caps"), QStringLiteral("grp:caps_toggle")},
};

// Alt+Shift и Ctrl+Shift — не параметром xkb (он переключает в момент
// нажатия: Alt+Shift+Tab, Ctrl+Shift+T меняли язык), а сочетанием KWin из
// одних модификаторов: срабатывает по отпусканию и только если между ними
// ничего не нажали — как в Windows. Не получилось назначить — xkb, как
// раньше. Экран входа остаётся на xkb (/etc/xdg/kxkbrc, свой KWin); то же
// делает kconf_update sedmio-layoutswitch для тех, кто уже входил.
const QHash<QString, int> kwinSwitchKeys = {
    {QStringLiteral("alt_shift"), int(Qt::ALT) | Qt::Key_Shift},
    {QStringLiteral("ctrl_shift"), int(Qt::CTRL) | Qt::Key_Shift},
};

const QStringList layoutAction = {QStringLiteral("KDE Keyboard Layout Switcher"),
                                  QStringLiteral("Switch to Next Keyboard Layout"),
                                  QString(),
                                  QString()};

QDBusMessage kglobalaccel(const QString &method)
{
    return QDBusMessage::createMethodCall(QStringLiteral("org.kde.kglobalaccel"),
                                          QStringLiteral("/kglobalaccel"),
                                          QStringLiteral("org.kde.KGlobalAccel"),
                                          method);
}
} // namespace

// Одно сочетание kglobalaccel — структура (ai): до четырёх клавиш подряд.
struct KeySequence {
    QList<int> keys;
};
Q_DECLARE_METATYPE(KeySequence)

QDBusArgument &operator<<(QDBusArgument &arg, const KeySequence &sequence)
{
    arg.beginStructure();
    arg << sequence.keys;
    arg.endStructure();
    return arg;
}

const QDBusArgument &operator>>(const QDBusArgument &arg, KeySequence &sequence)
{
    arg.beginStructure();
    arg >> sequence.keys;
    arg.endStructure();
    return arg;
}

namespace
{
// Клавиши действия KWin «следующая раскладка» (a(ai)); нет ответа — nullopt.
std::optional<QList<KeySequence>> layoutShortcut()
{
    qDBusRegisterMetaType<KeySequence>();
    qDBusRegisterMetaType<QList<KeySequence>>();
    QDBusMessage call = kglobalaccel(QStringLiteral("shortcutKeys"));
    call << layoutAction;
    const QDBusMessage reply = QDBusConnection::sessionBus().call(call, QDBus::Block, 3000);
    if (reply.type() != QDBusMessage::ReplyMessage || reply.arguments().isEmpty()
        || reply.signature() != QLatin1String("a(ai)"))
        return std::nullopt;
    QList<KeySequence> keys;
    reply.arguments().constFirst().value<QDBusArgument>() >> keys;
    return keys;
}

// Оставить у действия его клавиши без наших Alt+Shift и Ctrl+Shift и
// добавить key (0 — не добавлять). true — встало (проверено чтением).
bool setLayoutShortcut(int key)
{
    const auto current = layoutShortcut();
    if (!current)
        return false;
    QList<KeySequence> keys;
    for (const KeySequence &sequence : *current) {
        const int first = sequence.keys.value(0);
        if (first != 0 && std::find(kwinSwitchKeys.cbegin(), kwinSwitchKeys.cend(), first) == kwinSwitchKeys.cend())
            keys << sequence;
    }
    if (key != 0)
        keys << KeySequence{{key, 0, 0, 0}};

    QDBusMessage call = kglobalaccel(QStringLiteral("setForeignShortcutKeys"));
    call << layoutAction << QVariant::fromValue(keys);
    const QDBusMessage reply = QDBusConnection::sessionBus().call(call, QDBus::Block, 3000);
    if (reply.type() != QDBusMessage::ReplyMessage)
        return false;
    if (key == 0)
        return true;

    const auto now = layoutShortcut();
    return now && std::any_of(now->cbegin(), now->cend(), [key](const KeySequence &s) { return s.keys.value(0) == key; });
}

// Подпись раскладки, как на панели Windows (и нашей, KeyboardLayout.qml).
QString shortLabel(const QString &layout)
{
    static const QHash<QString, QString> labels = {
        {QStringLiteral("us"), QStringLiteral("ENG")}, {QStringLiteral("gb"), QStringLiteral("ENG")},
        {QStringLiteral("au"), QStringLiteral("ENG")}, {QStringLiteral("ie"), QStringLiteral("ENG")},
        {QStringLiteral("ru"), QStringLiteral("РУС")}, {QStringLiteral("ua"), QStringLiteral("УКР")},
        {QStringLiteral("by"), QStringLiteral("БЕЛ")}, {QStringLiteral("kz"), QStringLiteral("КАЗ")},
    };
    return labels.value(layout, layout.toUpper());
}

QString translate(const char *text)
{
    if (!text)
        return {};
    // Переводы описаний — у самого xkeyboard-config (домен сменил имя в 2.45).
    const char *translated = dgettext("xkeyboard-config-2", text);
    if (translated == text)
        translated = dgettext("xkeyboard-config", text);
    return QString::fromUtf8(translated);
}

struct Info {
    QString name;    // «Русская», «Английская (США)»
    QString english; // «Russian» — для поиска латиницей
};

// Названия раскладок и вариантов из реестра xkb, по «layout» и «layout(variant)».
const QHash<QString, Info> &registry()
{
    static const QHash<QString, Info> table = [] {
        QHash<QString, Info> result;
        rxkb_context *context = rxkb_context_new(RXKB_CONTEXT_NO_FLAGS);
        if (!context)
            return result;
        if (rxkb_context_parse_default_ruleset(context)) {
            for (rxkb_layout *layout = rxkb_layout_first(context); layout; layout = rxkb_layout_next(layout)) {
                const QString name = QString::fromUtf8(rxkb_layout_get_name(layout));
                const char *variant = rxkb_layout_get_variant(layout);
                const QString key = variant && *variant ? name + QLatin1Char('(') + QString::fromUtf8(variant) + QLatin1Char(')') : name;
                const char *description = rxkb_layout_get_description(layout);
                result.insert(key, {translate(description), QString::fromUtf8(description)});
            }
        }
        rxkb_context_unref(context);
        return result;
    }();
    return table;
}

QString configPath()
{
    return QStringLiteral("kxkbrc");
}
} // namespace

Keyboard::Keyboard(QObject *parent)
    : QObject(parent)
{
    load();
    loadRepeat();
    m_repeatSave.setSingleShot(true);
    m_repeatSave.setInterval(300);
    connect(&m_repeatSave, &QTimer::timeout, this, &Keyboard::saveRepeat);
}

// Закрыли окно, пока ползунок ещё «остывал», — сохранить сразу.
Keyboard::~Keyboard()
{
    if (m_repeatSave.isActive())
        saveRepeat();
}

// Значения по умолчанию — как у KWin (RepeatDelay 600, RepeatRate 25,
// NumLock 2 — «не трогать»; 0 — включить при входе, 1 — выключить).
void Keyboard::loadRepeat()
{
    KConfig config(QStringLiteral("kcminputrc"), KConfig::FullConfig);
    const KConfigGroup group(&config, QStringLiteral("Keyboard"));
    m_repeatDelay = std::clamp(group.readEntry("RepeatDelay", 600), 100, 2000);
    m_repeatRate = std::clamp(group.readEntry("RepeatRate", 25.0), 1.0, 100.0);
    m_numLockOn = group.readEntry("NumLock", 2) == 0;
    Q_EMIT repeatChanged();
}

void Keyboard::saveRepeat()
{
    KConfig config(QStringLiteral("kcminputrc"), KConfig::SimpleConfig);
    KConfigGroup group(&config, QStringLiteral("Keyboard"));
    // Notify — KWin перечитывает повтор сразу (KConfigWatcher).
    const auto flags = KConfig::Notify | KConfig::Persistent;
    group.writeEntry("RepeatDelay", m_repeatDelay, flags);
    group.writeEntry("RepeatRate", m_repeatRate, flags);
    if (m_numLockOn)
        group.writeEntry("NumLock", 0, flags);
    else
        group.deleteEntry("NumLock", flags);
    if (!config.sync()) {
        m_error = QStringLiteral("Не удалось сохранить повтор клавиш.");
        Q_EMIT changed();
    }
}

void Keyboard::setRepeatDelay(int ms)
{
    ms = std::clamp(ms, 100, 2000);
    if (ms == m_repeatDelay)
        return;
    m_repeatDelay = ms;
    Q_EMIT repeatChanged();
    m_repeatSave.start();
}

void Keyboard::setRepeatRate(double rate)
{
    rate = std::clamp(rate, 1.0, 100.0);
    if (qFuzzyCompare(rate, m_repeatRate))
        return;
    m_repeatRate = rate;
    Q_EMIT repeatChanged();
    m_repeatSave.start();
}

void Keyboard::setNumLockOn(bool on)
{
    if (on == m_numLockOn)
        return;
    m_numLockOn = on;
    Q_EMIT repeatChanged();
    saveRepeat();
}

void Keyboard::load()
{
    // KConfig сам сложит ~/.config/kxkbrc поверх /etc/xdg/kxkbrc (наши
    // значения по умолчанию из sedmio-settings).
    KConfig config(configPath(), KConfig::FullConfig);
    const KConfigGroup group(&config, QStringLiteral("Layout"));
    const QStringList layouts = group.readEntry("LayoutList", QString()).split(QLatin1Char(','), Qt::SkipEmptyParts);
    const QStringList variants = group.readEntry("VariantList", QString()).split(QLatin1Char(','));
    m_layouts.clear();
    for (int i = 0; i < layouts.size(); ++i)
        m_layouts.append({layouts[i].trimmed(), i < variants.size() ? variants[i].trimmed() : QString()});
    if (m_layouts.isEmpty())
        m_layouts.append({QStringLiteral("us"), QString()});

    m_otherOptions.clear();
    m_switchKey.clear();
    const QStringList options = group.readEntry("Options", QString()).split(QLatin1Char(','), Qt::SkipEmptyParts);
    for (const QString &option : options) {
        if (option.startsWith(QLatin1String("grp:"))) {
            m_switchKey = switchOptions.key(option);
            continue;
        }
        m_otherOptions.append(option);
    }
    // Alt+Shift, Ctrl+Shift — сочетанием KWin, параметра xkb нет; метка — SwitchKey.
    if (m_switchKey.isEmpty()) {
        const QString kwinKey = group.readEntry("SwitchKey", QString());
        if (kwinSwitchKeys.contains(kwinKey))
            m_switchKey = kwinKey;
    }
    m_perWindow = group.readEntry("SwitchMode", QStringLiteral("Global")) == QLatin1String("Window");
    m_savedSwitchKey = m_switchKey;
    Q_EMIT changed();
}

void Keyboard::save()
{
    KConfig config(configPath(), KConfig::SimpleConfig);
    KConfigGroup group(&config, QStringLiteral("Layout"));
    QStringList layouts;
    QStringList variants;
    for (const auto &layout : std::as_const(m_layouts)) {
        layouts << layout.layout;
        variants << layout.variant;
    }
    // Сначала клавиша KWin, потом параметр xkb: встала — xkb не нужен (иначе
    // язык переключался бы дважды); не встала — переключает xkb, как раньше.
    // kglobalaccel не ответил и прежнее сочетание KWin снять не вышло —
    // переключение не трогаем: с параметром xkb язык мог бы меняться дважды.
    const bool viaKWin = kwinSwitchKeys.contains(m_switchKey) && setLayoutShortcut(kwinSwitchKeys.value(m_switchKey));
    const bool keepSwitch = !viaKWin && !setLayoutShortcut(0);
    QStringList options = m_otherOptions;
    if (!viaKWin && switchOptions.contains(m_switchKey))
        options << switchOptions.value(m_switchKey);

    // Notify — KConfig сам разошлёт «настройки сменились», по нему KWin
    // перечитывает раскладки (KConfigWatcher).
    const auto flags = KConfig::Notify | KConfig::Persistent;
    group.writeEntry("Use", true, flags);
    group.writeEntry("LayoutList", layouts.join(QLatin1Char(',')), flags);
    group.writeEntry("VariantList", variants.join(QLatin1Char(',')), flags);
    group.writeEntry("ResetOldOptions", true, flags);
    if (!keepSwitch) {
        group.writeEntry("Options", options.join(QLatin1Char(',')), flags);
        if (viaKWin)
            group.writeEntry("SwitchKey", m_switchKey, flags);
        else
            group.deleteEntry("SwitchKey", flags);
    }
    group.writeEntry("SwitchMode", m_perWindow ? QStringLiteral("Window") : QStringLiteral("Global"), flags);
    if (!config.sync()) {
        m_error = QStringLiteral("Не удалось сохранить раскладки.");
        Q_EMIT changed();
        return;
    }
    m_error.clear();
    const bool switchChanged = m_switchKey != m_savedSwitchKey;
    if (!keepSwitch)
        m_savedSwitchKey = m_switchKey;
    if (keepSwitch && switchChanged) {
        load(); // показать клавишу, которая осталась
        m_error = QStringLiteral("Не удалось сменить клавиши переключения языка. Попробуйте ещё раз.");
    }

    // Старый способ (KWin до 6.x перечитывал по этому сигналу) — не мешает.
    QDBusConnection::sessionBus().send(
        QDBusMessage::createSignal(QStringLiteral("/Layouts"), QStringLiteral("org.kde.keyboard"), QStringLiteral("reloadConfig")));
    Q_EMIT changed();
}

QVariantList Keyboard::layouts() const
{
    QVariantList list;
    for (const auto &layout : m_layouts) {
        const QString key = layout.variant.isEmpty() ? layout.layout : layout.layout + QLatin1Char('(') + layout.variant + QLatin1Char(')');
        const Info info = registry().value(key, registry().value(layout.layout));
        list.append(QVariantMap{
            {QStringLiteral("layout"), layout.layout},
            {QStringLiteral("variant"), layout.variant},
            {QStringLiteral("name"), info.name.isEmpty() ? key : info.name},
            // Как на панели (и в Windows): ENG, РУС; остальные — кодом (DE).
            {QStringLiteral("short"), shortLabel(layout.layout)},
        });
    }
    return list;
}

QVariantList Keyboard::available() const
{
    struct Entry {
        QString layout;
        QString name;
        QString english;
    };
    QList<Entry> entries;
    for (auto it = registry().cbegin(); it != registry().cend(); ++it) {
        if (it.key().contains(QLatin1Char('(')))
            continue; // варианты не предлагаем: их почти никто не ищет
        if (std::any_of(m_layouts.cbegin(), m_layouts.cend(), [&](const Layout &l) { return l.layout == it.key() && l.variant.isEmpty(); }))
            continue;
        entries.append({it.key(), it.value().name.isEmpty() ? it.key() : it.value().name, it.value().english});
    }
    QCollator collator(QLocale(QLocale::Russian));
    std::sort(entries.begin(), entries.end(), [&](const Entry &a, const Entry &b) { return collator.compare(a.name, b.name) < 0; });

    QVariantList list;
    for (const auto &entry : entries) {
        list.append(QVariantMap{{QStringLiteral("layout"), entry.layout},
                                {QStringLiteral("name"), entry.name},
                                {QStringLiteral("search"),
                                 (entry.name + QLatin1Char(' ') + entry.english + QLatin1Char(' ') + entry.layout).toLower()}});
    }
    return list;
}

void Keyboard::add(const QString &layout)
{
    if (!registry().contains(layout) || m_layouts.size() >= 4) // xkb держит не больше четырёх
        return;
    m_layouts.append({layout, QString()});
    save();
}

void Keyboard::remove(int index)
{
    if (index < 0 || index >= m_layouts.size() || m_layouts.size() <= 1)
        return;
    m_layouts.removeAt(index);
    save();
}

void Keyboard::move(int index, int step)
{
    const int to = index + step;
    if (index < 0 || index >= m_layouts.size() || to < 0 || to >= m_layouts.size())
        return;
    m_layouts.swapItemsAt(index, to);
    save();
}

void Keyboard::setSwitchKey(const QString &key)
{
    if (key == m_switchKey || (!key.isEmpty() && !switchOptions.contains(key)))
        return;
    m_switchKey = key;
    save();
}

void Keyboard::setPerWindow(bool perWindow)
{
    if (perWindow == m_perWindow)
        return;
    m_perWindow = perWindow;
    save();
}
