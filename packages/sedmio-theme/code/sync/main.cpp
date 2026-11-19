// sedmio-theme-sync: цвета чужих программ (Qt/KDE, а через kde-gtk-config и
// GTK) — из темы Sedmio. Пишет схему ~/.local/share/color-schemes/Sedmio.colors
// (она перекрывает запасную /usr/share/color-schemes/Sedmio.colors из
// sedmio-settings) и, если у пользователя выбрана схема Sedmio или никакая,
// переносит её цвета в ~/.config/kdeglobals и сообщает запущенным программам.
// Своя схема у пользователя — её не трогаем, только обновляем файл Sedmio.
//
// Без аргументов — работает и следит за темой; --once — один раз и выйти.

#include "themedata.h"

#include <KConfig>
#include <KConfigGroup>

#include <QCoreApplication>
#include <QCryptographicHash>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusMetaType>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QSaveFile>
#include <QStandardPaths>
#include <QTextStream>

#include <cstdio>

namespace
{

QColor themeColor(const char *key)
{
    return Sedmio::ThemeData::instance()->color(QString::fromLatin1(key));
}

QColor mix(const QColor &a, const QColor &b, qreal t)
{
    return QColor::fromRgbF(a.redF() + (b.redF() - a.redF()) * t, a.greenF() + (b.greenF() - a.greenF()) * t,
                            a.blueF() + (b.blueF() - a.blueF()) * t);
}

QString rgb(const QColor &c)
{
    return QStringLiteral("%1,%2,%3").arg(c.red()).arg(c.green()).arg(c.blue());
}

bool isDark()
{
    return themeColor("paper").lightnessF() < 0.5;
}

using Group = QList<std::pair<QString, QString>>;

// Группа цветов KDE: фон и его чередование, текст обычный и прочий.
// Ссылки и цвета состояний (ошибка, внимание, успех) на тёмном фоне
// светлой темы (или на зелёном выделении) подмешиваются к тексту — иначе
// их не видно; accent — цвет ссылок и активного.
Group colorGroup(const QColor &background, const QColor &alternate, const QColor &foreground, const QColor &inactive,
                 const QColor &accent, qreal statusTowardText = 0)
{
    const QColor focus = themeColor("leaf");
    const auto status = [&](const char *key) {
        return mix(themeColor(key), foreground, statusTowardText);
    };
    const QColor visited = isDark() ? QColor(186, 160, 204) : QColor(122, 92, 140);
    return {
        {QStringLiteral("BackgroundAlternate"), rgb(alternate)},
        {QStringLiteral("BackgroundNormal"), rgb(background)},
        {QStringLiteral("DecorationFocus"), rgb(focus)},
        {QStringLiteral("DecorationHover"), rgb(focus)},
        {QStringLiteral("ForegroundActive"), rgb(accent)},
        {QStringLiteral("ForegroundInactive"), rgb(inactive)},
        {QStringLiteral("ForegroundLink"), rgb(accent)},
        {QStringLiteral("ForegroundNegative"), rgb(status("terracotta"))},
        {QStringLiteral("ForegroundNeutral"), rgb(status("warning"))},
        {QStringLiteral("ForegroundNormal"), rgb(foreground)},
        {QStringLiteral("ForegroundPositive"), rgb(status("success"))},
        {QStringLiteral("ForegroundVisited"), rgb(statusTowardText > 0 ? mix(visited, foreground, statusTowardText) : visited)},
    };
}

// Вся схема: [группа] → ключи. Порядок — как в схемах KDE.
QList<std::pair<QString, Group>> scheme()
{
    const QColor paper = themeColor("paper");
    const QColor paperDeep = themeColor("paperDeep");
    const QColor surface = themeColor("surface");
    const QColor ink = themeColor("ink");
    const QColor inkMuted = themeColor("inkMuted");
    const QColor green = themeColor("green");
    const QColor onGreen = themeColor("textOnGreen");

    // Тёмная полоса (Complementary): для светлой темы — из чернил,
    // для тёмной — ещё темнее бумаги.
    const QColor compBack = isDark() ? paperDeep : ink;
    const QColor compText = isDark() ? ink : paper;

    const QColor accent = themeColor("green");
    const QColor compAccent = isDark() ? accent : themeColor("greenWash");
    const auto group = [&](const QColor &background, const QColor &alternate) {
        return colorGroup(background, alternate, ink, inkMuted, accent);
    };

    return {
        {QStringLiteral("ColorEffects:Disabled"),
         {{QStringLiteral("Color"), rgb(mix(paper, ink, 0.25))},
          {QStringLiteral("ColorAmount"), QStringLiteral("0")},
          {QStringLiteral("ColorEffect"), QStringLiteral("0")},
          {QStringLiteral("ContrastAmount"), QStringLiteral("0.65")},
          {QStringLiteral("ContrastEffect"), QStringLiteral("1")},
          {QStringLiteral("IntensityAmount"), QStringLiteral("0.1")},
          {QStringLiteral("IntensityEffect"), QStringLiteral("2")}}},
        {QStringLiteral("ColorEffects:Inactive"),
         {{QStringLiteral("ChangeSelectionColor"), QStringLiteral("true")},
          {QStringLiteral("Color"), rgb(inkMuted)},
          {QStringLiteral("ColorAmount"), QStringLiteral("0.025")},
          {QStringLiteral("ColorEffect"), QStringLiteral("2")},
          {QStringLiteral("ContrastAmount"), QStringLiteral("0.1")},
          {QStringLiteral("ContrastEffect"), QStringLiteral("2")},
          {QStringLiteral("Enable"), QStringLiteral("false")},
          {QStringLiteral("IntensityAmount"), QStringLiteral("0")},
          {QStringLiteral("IntensityEffect"), QStringLiteral("0")}}},
        {QStringLiteral("Colors:Button"), group(surface, themeColor("greenWash"))},
        {QStringLiteral("Colors:Complementary"),
         colorGroup(compBack, mix(compBack, compText, 0.06), compText, mix(compText, compBack, 0.35), compAccent, isDark() ? 0 : 0.4)},
        {QStringLiteral("Colors:Header"), group(paperDeep, paper)},
        {QStringLiteral("Colors:Header][Inactive"), group(paper, paperDeep)},
        {QStringLiteral("Colors:Selection"),
         colorGroup(green, themeColor("greenWash"), onGreen, mix(onGreen, green, 0.3), onGreen, 0.6)},
        {QStringLiteral("Colors:Tooltip"), group(surface, paper)},
        {QStringLiteral("Colors:View"), group(surface, mix(surface, paper, 0.5))},
        {QStringLiteral("Colors:Window"), group(paper, paperDeep)},
        {QStringLiteral("KDE"), {{QStringLiteral("contrast"), QStringLiteral("4")}}},
        {QStringLiteral("WM"),
         {{QStringLiteral("activeBackground"), rgb(themeColor("windowTitle"))},
          {QStringLiteral("activeBlend"), rgb(themeColor("windowTitle"))},
          {QStringLiteral("activeForeground"), rgb(ink)},
          {QStringLiteral("inactiveBackground"), rgb(themeColor("windowTitleInactive"))},
          {QStringLiteral("inactiveBlend"), rgb(themeColor("windowTitleInactive"))},
          {QStringLiteral("inactiveForeground"), rgb(inkMuted)}}},
    };
}

// Группа kdeglobals по имени из схемы ("Colors:Header][Inactive" — вложенная).
KConfigGroup configGroup(KConfig &config, const QString &name)
{
    const QStringList parts = name.split(QStringLiteral("]["));
    KConfigGroup group = config.group(parts.first());
    for (qsizetype i = 1; i < parts.size(); ++i)
        group = group.group(parts.at(i));
    return group;
}

QString schemePath()
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + QStringLiteral("/color-schemes/Sedmio.colors");
}

bool writeSchemeFile(const QList<std::pair<QString, Group>> &groups)
{
    const QString path = schemePath();
    const QString dir = QFileInfo(path).path();

    QString text;
    QTextStream out(&text);
    out << "# Создано sedmio-theme-sync из темы Sedmio «" << Sedmio::ThemeData::instance()->string(QStringLiteral("themeName"))
        << "». Правки затрутся: цвета меняются в теме.\n";
    for (const auto &[name, keys] : groups) {
        out << "\n[" << name << "]\n";
        for (const auto &[key, value] : keys)
            out << key << '=' << value << '\n';
    }
    out << "\n[General]\nColorScheme=Sedmio\nName=Sedmio\nshadeSortColumn=true\n";
    out.flush();

    QFile current(path);
    if (current.open(QIODevice::ReadOnly) && QString::fromUtf8(current.readAll()) == text)
        return true;
    current.close();

    QDir().mkpath(dir);
    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly)) {
        std::fprintf(stderr, "sedmio-theme-sync: не записать %s\n", qPrintable(path));
        return false;
    }
    file.write(text.toUtf8());
    return file.commit();
}

// Перенести цвета в kdeglobals, если выбрана схема Sedmio или никакая.
void applyToKdeGlobals(const QList<std::pair<QString, Group>> &groups)
{
    // Только файл пользователя: умолчания Plasma (kdedefaults) — не выбор.
    // Имя, а не путь: по нему KConfig::Notify шлёт сигнал (/kdeglobals).
    KConfig config(QStringLiteral("kdeglobals"), KConfig::SimpleConfig);
    KConfigGroup general = config.group(QStringLiteral("General"));
    const QString chosen = general.readEntry("ColorScheme", QString());
    if (!chosen.isEmpty() && chosen != QLatin1String("Sedmio"))
        return;

    bool changed = false;
    const auto write = [&changed](KConfigGroup group, const QString &key, const QString &value) {
        if (group.readEntry(key, QString()) == value)
            return;
        group.writeEntry(key, value, KConfig::Notify);
        changed = true;
    };
    for (const auto &[name, keys] : groups) {
        KConfigGroup group = configGroup(config, name);
        for (const auto &[key, value] : keys)
            write(group, key, value);
    }
    write(general, QStringLiteral("ColorScheme"), QStringLiteral("Sedmio"));
    // Хэш файла схемы: Plasma при входе сверяет его и, если не совпал,
    // применяет схему ещё раз — лишняя перерисовка всех программ.
    QFile file(schemePath());
    if (file.open(QIODevice::ReadOnly))
        write(general, QStringLiteral("ColorSchemeHash"),
              QString::fromLatin1(QCryptographicHash::hash(file.readAll(), QCryptographicHash::Sha1).toHex()));
    if (!changed)
        return;
    config.sync();

    // kde-gtk-config перекрашивает GTK, только когда меняется ключ
    // ColorScheme, а у нас имя то же — сказать ему, будто поменялся
    // (тот же сигнал, что шлёт KConfig::Notify).
    qDBusRegisterMetaType<QByteArrayList>();
    qDBusRegisterMetaType<QHash<QString, QByteArrayList>>();
    QDBusMessage configChanged = QDBusMessage::createSignal(QStringLiteral("/kdeglobals"), QStringLiteral("org.kde.kconfig.notify"),
                                                            QStringLiteral("ConfigChanged"));
    const QHash<QString, QByteArrayList> keys{{QStringLiteral("General"), {QByteArrayLiteral("ColorScheme")}}};
    configChanged.setArguments({QVariant::fromValue(keys)});
    QDBusConnection::sessionBus().send(configChanged);

    // Программам KDE — палитра поменялась (как plasma-apply-colorscheme).
    QDBusMessage message = QDBusMessage::createSignal(QStringLiteral("/KGlobalSettings"), QStringLiteral("org.kde.KGlobalSettings"),
                                                      QStringLiteral("notifyChange"));
    message.setArguments({0 /* PaletteChanged */, 0});
    QDBusConnection::sessionBus().send(message);
}

void sync()
{
    const auto groups = scheme();
    if (writeSchemeFile(groups))
        applyToKdeGlobals(groups);
}

} // namespace

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("sedmio-theme-sync"));

    sync();
    if (app.arguments().contains(QStringLiteral("--once")))
        return 0;

    QObject::connect(Sedmio::ThemeData::instance(), &Sedmio::ThemeData::changed, &app, &sync);
    return app.exec();
}
