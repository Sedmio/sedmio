#pragma once

#include <KDecoration3/DecorationButton>

namespace Sedmio
{

// Кнопка в заголовке: кружок при наведении, значок линиями (закрыть —
// терракотовый кружок). Что делать по нажатию, знает KDecoration сам.
class Button : public KDecoration3::DecorationButton
{
    Q_OBJECT

public:
    // nullptr — такой кнопки у нас нет (её не будет в заголовке).
    static KDecoration3::DecorationButton *create(KDecoration3::DecorationButtonType type, KDecoration3::Decoration *decoration,
                                                  QObject *parent);

    void paint(QPainter *painter, const QRectF &repaintArea) override;

private:
    Button(KDecoration3::DecorationButtonType type, KDecoration3::Decoration *decoration, QObject *parent);
    void paintGlyph(QPainter *painter, const QRectF &rect, const QColor &color) const;
};

} // namespace Sedmio
