#pragma once

#include <KDecoration3/DecorationShadow>

#include <QColor>

#include <memory>

namespace Sedmio
{

// Тень окна: размытый скруглённый прямоугольник, чуть ниже окна. Готовые
// тени общие для всех окон (одна картинка на сочетание параметров);
// тени, которые ни одно окно уже не держит, выбрасываются при новой.
std::shared_ptr<KDecoration3::DecorationShadow> windowShadow(const QColor &color, qreal strength, qreal radius);

} // namespace Sedmio
