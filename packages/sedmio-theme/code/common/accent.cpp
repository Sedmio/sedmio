#include "accent.h"

#include <QFile>
#include <QImage>
#include <QImageReader>
#include <QRegularExpression>
#include <QStandardPaths>

#include <algorithm>
#include <array>
#include <cmath>

namespace
{

// OKLab (Björn Ottosson): равные шаги L — равная на глаз светлота,
// поэтому смена оттенка не меняет читаемость.
struct Lab {
    double l, a, b;
};

double toLinear(double c)
{
    return c <= 0.04045 ? c / 12.92 : std::pow((c + 0.055) / 1.055, 2.4);
}

double fromLinear(double c)
{
    return c <= 0.0031308 ? c * 12.92 : 1.055 * std::pow(c, 1 / 2.4) - 0.055;
}

Lab toLab(double r, double g, double b)
{
    r = toLinear(r);
    g = toLinear(g);
    b = toLinear(b);
    const double l = std::cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
    const double m = std::cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
    const double s = std::cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
    return {0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s, 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
            0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s};
}

Lab toLab(const QColor &c)
{
    return toLab(c.redF(), c.greenF(), c.blueF());
}

// Линейные r, g, b; вне [0, 1] — цвета нет на экране.
std::array<double, 3> toLinearRgb(const Lab &c)
{
    const double l = std::pow(c.l + 0.3963377774 * c.a + 0.2158037573 * c.b, 3);
    const double m = std::pow(c.l - 0.1055613458 * c.a - 0.0638541728 * c.b, 3);
    const double s = std::pow(c.l - 0.0894841775 * c.a - 1.2914855480 * c.b, 3);
    return {4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s, -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
            -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s};
}

bool inGamut(const std::array<double, 3> &rgb)
{
    return std::all_of(rgb.begin(), rgb.end(), [](double v) {
        return v >= -1e-4 && v <= 1 + 1e-4;
    });
}

// Светлота l, насыщенность c, оттенок h (радианы). Не помещается в sRGB —
// насыщенность меньше, светлота и оттенок те же.
QColor fromLch(double l, double c, double h, qreal alpha)
{
    auto lab = [&](double chroma) {
        return Lab{l, chroma * std::cos(h), chroma * std::sin(h)};
    };
    if (!inGamut(toLinearRgb(lab(c)))) {
        double lo = 0, hi = c;
        for (int i = 0; i < 20; ++i) {
            const double mid = (lo + hi) / 2;
            (inGamut(toLinearRgb(lab(mid))) ? lo : hi) = mid;
        }
        c = lo;
    }
    const auto rgb = toLinearRgb(lab(c));
    const auto channel = [](double v) {
        return std::clamp(fromLinear(std::clamp(v, 0.0, 1.0)), 0.0, 1.0);
    };
    return QColor::fromRgbF(channel(rgb[0]), channel(rgb[1]), channel(rgb[2]), alpha);
}

double chroma(const Lab &c)
{
    return std::hypot(c.a, c.b);
}

double hue(const Lab &c)
{
    return std::atan2(c.b, c.a);
}

// Насыщенность, ниже которой оттенка у цвета, считай, нет.
constexpr double grey = 0.015;

} // namespace

namespace Sedmio::Accent
{

QString modeFile()
{
    return QStandardPaths::locate(QStandardPaths::GenericConfigLocation, QStringLiteral("sedmio/accent"));
}

bool fromWallpaper()
{
    const QString path = modeFile();
    if (path.isEmpty())
        return false;
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
        return false;
    return QString::fromUtf8(file.readLine(64)).trimmed() == QLatin1String("wallpaper");
}

QString stateFile()
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericStateLocation) + QStringLiteral("/sedmio/accent/wallpaper");
}

QColor stateColor()
{
    QFile file(stateFile());
    if (!file.open(QIODevice::ReadOnly))
        return {};
    static const QRegularExpression rgb(QStringLiteral("^#[0-9A-Fa-f]{6}$"));
    const QString line = QString::fromUtf8(file.readLine(64)).trimmed();
    return rgb.match(line).hasMatch() ? QColor::fromString(line) : QColor();
}

QColor fromImage(const QString &path)
{
    QImageReader reader(path);
    reader.setAutoTransform(true);
    // JPEG так и читается уменьшенным — большая картинка в память целиком
    // не встаёт.
    const QSize size = reader.size();
    if (size.isValid())
        reader.setScaledSize(size.scaled(64, 64, Qt::KeepAspectRatio).expandedTo(QSize(1, 1)));
    QImage image = reader.read();
    if (image.isNull())
        return {};
    if (image.width() > 64 || image.height() > 64)
        image = image.scaled(64, 64, Qt::KeepAspectRatio, Qt::SmoothTransformation);
    image.convertTo(QImage::Format_RGB32);

    // Оттенки — 36 корзин по 10°. Вес точки — её насыщенность: серое
    // и почти серое оттенок не выбирает. Очень тёмное и очень светлое —
    // тоже нет: у него оттенок на глаз не виден.
    constexpr int bins = 36;
    struct Bin {
        double weight = 0, a = 0, b = 0, l = 0, c = 0;
    };
    std::array<Bin, bins> hist{};
    double totalL = 0;
    int count = 0;
    for (int y = 0; y < image.height(); ++y) {
        const QRgb *line = reinterpret_cast<const QRgb *>(image.constScanLine(y));
        for (int x = 0; x < image.width(); ++x) {
            const Lab p = toLab(qRed(line[x]) / 255.0, qGreen(line[x]) / 255.0, qBlue(line[x]) / 255.0);
            totalL += p.l;
            ++count;
            const double c = chroma(p);
            if (p.l < 0.2 || p.l > 0.95 || c < grey)
                continue;
            const double h = hue(p);
            const int i = std::clamp(int((h + M_PI) / (2 * M_PI) * bins), 0, bins - 1);
            Bin &bin = hist[i];
            bin.weight += c;
            bin.a += p.a * c;
            bin.b += p.b * c;
            bin.l += p.l * c;
            bin.c += c * c;
        }
    }
    if (count == 0)
        return {};

    // Самая весомая корзина вместе с соседними: оттенок на границе двух
    // корзин не теряется.
    int best = -1;
    double bestWeight = 0;
    for (int i = 0; i < bins; ++i) {
        const double w = hist[i].weight + 0.5 * (hist[(i + 1) % bins].weight + hist[(i + bins - 1) % bins].weight);
        if (w > bestWeight) {
            bestWeight = w;
            best = i;
        }
    }
    // Цветного почти нет (меньше 1 % картинки, будь она вся насыщенной) —
    // обои серые.
    if (best < 0 || bestWeight < count * 0.1 * 0.01)
        return fromLch(totalL / count, 0, 0, 1);

    Bin sum;
    for (int d = -1; d <= 1; ++d) {
        const Bin &bin = hist[(best + d + bins) % bins];
        sum.weight += bin.weight;
        sum.a += bin.a;
        sum.b += bin.b;
        sum.l += bin.l;
        sum.c += bin.c;
    }
    const Lab mean{sum.l / sum.weight, sum.a / sum.weight, sum.b / sum.weight};
    // Насыщенность — средняя по точкам этого оттенка (не по среднему цвету:
    // он у разбросанных оттенков сероватый).
    return fromLch(mean.l, sum.c / sum.weight, hue(mean), 1);
}

void apply(QVariantMap &values, const QColor &source)
{
    const QColor base = values.value(QStringLiteral("green")).value<QColor>();
    if (!source.isValid() || !base.isValid())
        return;
    const Lab s = toLab(source);
    const Lab g = toLab(base);
    const bool colorless = chroma(s) < grey;
    // Поворот оттенка от акцента темы к обоям — для всех ключей один:
    // соотношения цветов темы (лист чуть желтее зелени) остаются.
    const double turn = colorless ? 0 : hue(s) - hue(g);
    const double scale = std::clamp(chroma(s) / std::max(chroma(g), 0.01), 0.25, 1.5);
    for (const QString &key : keys) {
        const QColor color = values.value(key).value<QColor>();
        if (!color.isValid())
            continue;
        const Lab c = toLab(color);
        values.insert(key, fromLch(c.l, chroma(c) * scale, hue(c) + turn, color.alphaF()));
    }
}

} // namespace Sedmio::Accent
