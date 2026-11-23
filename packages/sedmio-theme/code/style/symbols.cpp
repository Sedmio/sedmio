#include "symbols.h"

#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QStandardPaths>

#include <algorithm>

Symbols::Symbols(QObject *parent)
    : QObject(parent)
{
    const QString names = QStandardPaths::locate(QStandardPaths::GenericDataLocation, QStringLiteral("sedmio/symbols/names.json"));
    if (names.isEmpty())
        return;
    m_dir = names.section(QLatin1Char('/'), 0, -2) + QStringLiteral("/lucide/");
    QFile file(names);
    if (!file.open(QIODevice::ReadOnly))
        return;
    const QJsonObject map = QJsonDocument::fromJson(file.readAll()).object();
    for (auto it = map.begin(); it != map.end(); ++it) {
        if (it.key() != QLatin1String("_") && it.value().isString())
            m_names.insert(it.key(), it.value().toString());
    }
}

QString Symbols::fileFor(const QString &name) const
{
    QString key = name;
    if (key.endsWith(QLatin1String("-symbolic")))
        key.chop(9);
    return m_names.value(key);
}

bool Symbols::has(const QString &name) const
{
    return !fileFor(name).isEmpty();
}

QString Symbols::url(const QString &name, const QColor &color, qreal size) const
{
    const QString file = fileFor(name);
    if (file.isEmpty())
        return {};
    auto it = m_svg.find(file);
    if (it == m_svg.end()) {
        QFile f(m_dir + file + QStringLiteral(".svg"));
        it = m_svg.insert(file, f.open(QIODevice::ReadOnly) ? f.readAll() : QByteArray());
    }
    if (it->isEmpty())
        return {};

    QByteArray svg = *it;
    const QColor c = color.isValid() ? color : QColor(Qt::black);
    svg.replace("currentColor", c.name(QColor::HexRgb).toLatin1());
    // Рисунок 24×24: линия в 1,5 пикселя на экране при размере size.
    const qreal stroke = std::clamp(1.5 * 24 / std::max<qreal>(size, 8), 1.25, 2.5);
    svg.replace("stroke-width=\"2\"", "stroke-width=\"" + QByteArray::number(stroke, 'f', 2) + '"');
    if (c.alpha() < 255)
        svg.replace("<svg ", "<svg opacity=\"" + QByteArray::number(c.alphaF(), 'f', 3) + "\" ");
    return QStringLiteral("data:image/svg+xml;base64,") + QString::fromLatin1(svg.toBase64());
}
