#pragma once

#include <QColor>
#include <QString>
#include <QVariantMap>

// Акцентный цвет из обоев. Включается первой строкой «wallpaper» в
// sedmio/accent (сначала ~/.config, потом /etc/xdg). Цвет картинки
// находит sedmio-theme-sync — один раз на смену обоев — и пишет в
// ~/.local/state/sedmio/accent/wallpaper; ThemeData перекрашивает в его
// оттенок акцентные цвета любой темы. Светлота и соотношения цветов темы
// остаются, поэтому текст на кнопках читается так же.
namespace Sedmio::Accent
{

// Ключи темы, которые красятся в цвет обоев (terracotta, success и
// прочие цвета-смыслы — нет).
inline const QStringList keys = {QStringLiteral("green"), QStringLiteral("greenWash"), QStringLiteral("greenSelect"),
                                 QStringLiteral("textOnGreen"), QStringLiteral("leaf")};

QString modeFile();      // sedmio/accent, по которому решаем (может не быть)
bool fromWallpaper();    // включено ли
QString stateFile();     // ~/.local/state/sedmio/accent/wallpaper
QColor stateColor();     // цвет из stateFile, или недействительный

// Цвет картинки для акцента: самый заметный оттенок из насыщенных
// (на картинку смотрим уменьшенной до 64 точек). Не открылась —
// недействительный цвет; серая — серый.
QColor fromImage(const QString &path);

// Повернуть акцентные цвета values к оттенку source; насыщенность — по
// source (серые обои — приглушённый акцент той же темы).
void apply(QVariantMap &values, const QColor &source);

} // namespace Sedmio::Accent
