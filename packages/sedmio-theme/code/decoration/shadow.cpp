#include "shadow.h"

#include <QHash>
#include <QImage>
#include <QPainter>
#include <QPainterPath>

#include <algorithm>
#include <cmath>
#include <vector>

namespace Sedmio
{
namespace
{
// Насколько тень выходит за окно, насколько она ниже окна и как размыта.
constexpr int extent = 32;
constexpr int offset = 8;
constexpr int blurRadius = 11;

QHash<QString, std::shared_ptr<KDecoration3::DecorationShadow>> &cache()
{
    static QHash<QString, std::shared_ptr<KDecoration3::DecorationShadow>> shadows;
    return shadows;
}

// Один проход сглаживания по строкам или столбцам (скользящее среднее).
void boxBlur(std::vector<float> &values, int width, int height, int radius, bool horizontal)
{
    const int lines = horizontal ? height : width;
    const int length = horizontal ? width : height;
    std::vector<float> line(length);
    for (int l = 0; l < lines; ++l) {
        const auto at = [&](int i) -> float & {
            return horizontal ? values[l * width + i] : values[i * width + l];
        };
        for (int i = 0; i < length; ++i)
            line[i] = at(i);
        float sum = 0;
        for (int i = -radius; i <= radius; ++i)
            sum += line[std::clamp(i, 0, length - 1)];
        const float scale = 1.0f / float(2 * radius + 1);
        for (int i = 0; i < length; ++i) {
            at(i) = sum * scale;
            sum += line[std::min(i + radius + 1, length - 1)] - line[std::max(i - radius, 0)];
        }
    }
}
} // namespace

std::shared_ptr<KDecoration3::DecorationShadow> windowShadow(const QColor &color, qreal strength, qreal radius)
{
    const QString key = QStringLiteral("%1/%2/%3").arg(color.name(QColor::HexArgb)).arg(strength).arg(radius);
    if (auto shadow = cache().value(key))
        return shadow;

    // Окно в картинке — квадрат, в котором помещаются оба скругления;
    // KWin растягивает середину картинки по размеру окна.
    const int box = int(std::ceil(2 * radius)) + 2 * extent;
    const int width = box + 2 * extent;
    const int height = box + 2 * extent;
    const QRectF window(extent, extent - offset, box, box);

    // Тень от окна, сдвинутого вниз, — размыть.
    QImage shape(width, height, QImage::Format_ARGB32_Premultiplied);
    shape.fill(Qt::transparent);
    {
        QPainter p(&shape);
        p.setRenderHint(QPainter::Antialiasing);
        p.setPen(Qt::NoPen);
        p.setBrush(Qt::black);
        p.drawRoundedRect(window.translated(0, offset), radius, radius);
    }
    std::vector<float> alpha(size_t(width) * height);
    for (int y = 0; y < height; ++y) {
        const QRgb *row = reinterpret_cast<const QRgb *>(shape.constScanLine(y));
        for (int x = 0; x < width; ++x)
            alpha[size_t(y) * width + x] = qAlpha(row[x]) / 255.0f;
    }
    for (int pass = 0; pass < 3; ++pass) {
        boxBlur(alpha, width, height, blurRadius, true);
        boxBlur(alpha, width, height, blurRadius, false);
    }

    QImage image(width, height, QImage::Format_ARGB32_Premultiplied);
    const float base = float(color.alphaF() * strength);
    for (int y = 0; y < height; ++y) {
        QRgb *row = reinterpret_cast<QRgb *>(image.scanLine(y));
        for (int x = 0; x < width; ++x) {
            const int a = std::clamp(int(alpha[size_t(y) * width + x] * base * 255.0f + 0.5f), 0, 255);
            row[x] = qPremultiply(qRgba(color.red(), color.green(), color.blue(), a));
        }
    }
    // Под самим окном тени нет: просвечивала бы сквозь полупрозрачное.
    {
        QPainter p(&image);
        p.setRenderHint(QPainter::Antialiasing);
        p.setCompositionMode(QPainter::CompositionMode_DestinationOut);
        p.setPen(Qt::NoPen);
        p.setBrush(Qt::black);
        p.drawRoundedRect(window, radius, radius);
    }

    auto shadow = std::make_shared<KDecoration3::DecorationShadow>();
    shadow->setPadding(QMarginsF(extent, extent - offset, extent, extent + offset));
    shadow->setInnerShadowRect(QRectF(window.center(), QSizeF(1, 1)));
    shadow->setShadow(image);
    // Тени прежних тем, которых уже нет ни у одного окна, — выбросить.
    cache().removeIf([](const auto &it) {
        return it.value().use_count() == 1;
    });
    cache().insert(key, shadow);
    return shadow;
}

} // namespace Sedmio
