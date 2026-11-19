#include "keyboard.h"

#include <KConfig>
#include <KConfigGroup>

#include <QCollator>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QHash>

#include <xkbcommon/xkbregistry.h>

#include <libintl.h>

#include <algorithm>

namespace
{
// Переключение — параметр xkb из группы grp:.
const QHash<QString, QString> switchOptions = {
    {QStringLiteral("alt_shift"), QStringLiteral("grp:alt_shift_toggle")},
    {QStringLiteral("ctrl_shift"), QStringLiteral("grp:ctrl_shift_toggle")},
    {QStringLiteral("win_space"), QStringLiteral("grp:win_space_toggle")},
    {QStringLiteral("caps"), QStringLiteral("grp:caps_toggle")},
};

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
    m_perWindow = group.readEntry("SwitchMode", QStringLiteral("Global")) == QLatin1String("Window");
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
    QStringList options = m_otherOptions;
    if (switchOptions.contains(m_switchKey))
        options << switchOptions.value(m_switchKey);

    // Notify — KConfig сам разошлёт «настройки сменились», по нему KWin
    // перечитывает раскладки (KConfigWatcher).
    const auto flags = KConfig::Notify | KConfig::Persistent;
    group.writeEntry("Use", true, flags);
    group.writeEntry("LayoutList", layouts.join(QLatin1Char(',')), flags);
    group.writeEntry("VariantList", variants.join(QLatin1Char(',')), flags);
    group.writeEntry("ResetOldOptions", true, flags);
    group.writeEntry("Options", options.join(QLatin1Char(',')), flags);
    group.writeEntry("SwitchMode", m_perWindow ? QStringLiteral("Window") : QStringLiteral("Global"), flags);
    if (!config.sync()) {
        m_error = QStringLiteral("Не удалось сохранить раскладки.");
        Q_EMIT changed();
        return;
    }
    m_error.clear();

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
            // Как на панели: код раскладки (US, RU).
            {QStringLiteral("short"), layout.layout.toUpper()},
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
