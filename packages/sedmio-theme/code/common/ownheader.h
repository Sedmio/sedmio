#pragma once

#include <QDir>
#include <QFile>
#include <QString>
#include <QStringList>

namespace Sedmio
{

// Наши программы рисуют заголовок окна сами: боковая панель и полоса
// инструментов доходят до верха окна, кнопки окна — Sedmio.Style
// WindowControls, перетаскивание — WindowDragArea. Рамка Sedmio у таких
// окон полосу заголовка не рисует — оставляет скругление, контур, тень и
// края для растягивания.
//
// Только главные окна: модальные и окна постоянного размера (диалоги,
// «Свойства») — с обычным заголовком рамки. Окно узнаём по app_id
// (QGuiApplication::desktopFileName программы).
inline bool drawsOwnHeader(const QString &windowClass)
{
    static const QStringList apps{
        QStringLiteral("sedmio-preferences"),
        QStringLiteral("sedmio-store"),
        QStringLiteral("sedmio-files"),
        QStringLiteral("sedmio-tasks"),
        QStringLiteral("sedmio-screenshot-editor"),
    };
    // У KWin это «имя_файла app_id».
    const QStringList parts = windowClass.split(QLatin1Char(' '), Qt::SkipEmptyParts);
    for (const QString &part : parts) {
        if (apps.contains(part))
            return true;
    }
    return false;
}

// Рамки окон KWin — наши (kwinrc, [org.kde.kdecoration2] library): свои
// настройки человека, иначе общие из /etc/xdg. Нет ни там, ни там — KWin
// рисует Breeze.
inline bool ourDecoration()
{
    QString home = qEnvironmentVariable("XDG_CONFIG_HOME");
    if (home.isEmpty())
        home = QDir::homePath() + QStringLiteral("/.config");
    const QStringList files{home + QStringLiteral("/kwinrc"), QStringLiteral("/etc/xdg/kwinrc")};
    for (const QString &path : files) {
        QFile file(path);
        if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
            continue;
        bool inGroup = false;
        while (!file.atEnd()) {
            const QString line = QString::fromUtf8(file.readLine()).trimmed();
            if (line.startsWith(QLatin1Char('['))) {
                inGroup = line == QLatin1String("[org.kde.kdecoration2]");
                continue;
            }
            if (!inGroup)
                continue;
            const qsizetype eq = line.indexOf(QLatin1Char('='));
            if (eq < 0)
                continue;
            QString key = line.left(eq).trimmed();
            // library[$i] — то же, только неизменяемое.
            const qsizetype bracket = key.indexOf(QLatin1Char('['));
            if (bracket > 0)
                key = key.left(bracket);
            if (key == QLatin1String("library"))
                return line.mid(eq + 1).trimmed() == QLatin1String("org.sedmio.decoration");
        }
    }
    return false;
}

} // namespace Sedmio
