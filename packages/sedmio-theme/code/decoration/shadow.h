#pragma once

#include <KDecoration3/DecorationShadow>

#include <QColor>

#include <memory>

namespace Sedmio
{

// Тень окна: размытый скруглённый прямоугольник, чуть ниже окна. Готовые
// тени общие для всех окон (одна картинка на сочетание параметров).
std::shared_ptr<KDecoration3::DecorationShadow> windowShadow(const QColor &color, qreal strength, qreal radius);

// Тема поменялась — старые картинки больше не нужны.
void clearShadowCache();

} // namespace Sedmio
