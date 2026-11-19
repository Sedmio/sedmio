#include "button.h"

#include "decoration.h"

#include <KDecoration3/DecoratedWindow>

#include <QPainter>
#include <QPainterPath>

namespace Sedmio
{

using KDecoration3::DecorationButtonType;

KDecoration3::DecorationButton *Button::create(DecorationButtonType type, KDecoration3::Decoration *decoration, QObject *parent)
{
    switch (type) {
    case DecorationButtonType::Menu:
    case DecorationButtonType::Minimize:
    case DecorationButtonType::Maximize:
    case DecorationButtonType::Close:
    case DecorationButtonType::OnAllDesktops:
    case DecorationButtonType::KeepAbove:
    case DecorationButtonType::KeepBelow:
    case DecorationButtonType::Shade:
    case DecorationButtonType::ContextHelp:
        return new Button(type, decoration, parent);
    default:
        return nullptr;
    }
}

Button::Button(DecorationButtonType type, KDecoration3::Decoration *decoration, QObject *parent)
    : KDecoration3::DecorationButton(type, decoration, parent)
{
    const auto repaint = [this] {
        update();
    };
    connect(this, &DecorationButton::hoveredChanged, this, repaint);
    connect(this, &DecorationButton::pressedChanged, this, repaint);
    connect(this, &DecorationButton::checkedChanged, this, repaint);

    KDecoration3::DecoratedWindow *w = decoration->window();
    switch (type) {
    case DecorationButtonType::Minimize:
        setVisible(w->isMinimizeable());
        connect(w, &KDecoration3::DecoratedWindow::minimizeableChanged, this, &DecorationButton::setVisible);
        break;
    case DecorationButtonType::Maximize:
        setVisible(w->isMaximizeable());
        setCheckable(true);
        setChecked(w->isMaximized());
        connect(w, &KDecoration3::DecoratedWindow::maximizeableChanged, this, &DecorationButton::setVisible);
        connect(w, &KDecoration3::DecoratedWindow::maximizedChanged, this, &DecorationButton::setChecked);
        break;
    case DecorationButtonType::Close:
        setVisible(w->isCloseable());
        connect(w, &KDecoration3::DecoratedWindow::closeableChanged, this, &DecorationButton::setVisible);
        break;
    case DecorationButtonType::ContextHelp:
        setVisible(w->providesContextHelp());
        connect(w, &KDecoration3::DecoratedWindow::providesContextHelpChanged, this, &DecorationButton::setVisible);
        break;
    case DecorationButtonType::OnAllDesktops:
        setCheckable(true);
        setChecked(w->isOnAllDesktops());
        connect(w, &KDecoration3::DecoratedWindow::onAllDesktopsChanged, this, &DecorationButton::setChecked);
        break;
    case DecorationButtonType::KeepAbove:
        setCheckable(true);
        setChecked(w->isKeepAbove());
        connect(w, &KDecoration3::DecoratedWindow::keepAboveChanged, this, &DecorationButton::setChecked);
        break;
    case DecorationButtonType::KeepBelow:
        setCheckable(true);
        setChecked(w->isKeepBelow());
        connect(w, &KDecoration3::DecoratedWindow::keepBelowChanged, this, &DecorationButton::setChecked);
        break;
    case DecorationButtonType::Shade:
        setVisible(w->isShadeable());
        setCheckable(true);
        setChecked(w->isShaded());
        connect(w, &KDecoration3::DecoratedWindow::shadeableChanged, this, &DecorationButton::setVisible);
        connect(w, &KDecoration3::DecoratedWindow::shadedChanged, this, &DecorationButton::setChecked);
        break;
    case DecorationButtonType::Menu:
        connect(w, &KDecoration3::DecoratedWindow::iconChanged, this, repaint);
        break;
    default:
        break;
    }
}

void Button::paint(QPainter *painter, const QRectF &repaintArea)
{
    Q_UNUSED(repaintArea)
    if (!isVisible())
        return;
    auto *deco = qobject_cast<Sedmio::Decoration *>(decoration());
    if (!deco)
        return;

    const QRectF rect = geometry();
    painter->save();
    painter->setRenderHint(QPainter::Antialiasing);

    if (type() == DecorationButtonType::Menu) {
        const qreal size = std::min<qreal>(18, rect.height());
        const QRectF iconRect(rect.center().x() - size / 2, rect.center().y() - size / 2, size, size);
        deco->window()->icon().paint(painter, iconRect.toRect());
        painter->restore();
        return;
    }

    const bool close = type() == DecorationButtonType::Close;
    const bool active = deco->isActive();

    // Кружок: наведено, нажато или включено (поверх всех окон и т. п.).
    QColor background;
    if (close && (isHovered() || isPressed())) {
        background = deco->themeColor(QStringLiteral("terracotta"));
        if (isPressed())
            background = background.darker(115);
    } else if (isPressed()) {
        background = deco->themeColor(QStringLiteral("greenSelect"));
    } else if (isHovered()) {
        background = deco->themeColor(QStringLiteral("greenWash"));
    } else if (isChecked() && type() != DecorationButtonType::Maximize) {
        background = deco->themeColor(QStringLiteral("greenWash"));
    }
    if (background.isValid()) {
        painter->setPen(Qt::NoPen);
        painter->setBrush(background);
        painter->drawEllipse(rect.adjusted(1, 1, -1, -1));
    }

    QColor glyph = deco->themeColor(active ? QStringLiteral("inkSoft") : QStringLiteral("inkMuted"));
    if (close && (isHovered() || isPressed()))
        glyph = deco->themeColor(QStringLiteral("textOnGreen"));
    paintGlyph(painter, rect, glyph);
    painter->restore();
}

void Button::paintGlyph(QPainter *painter, const QRectF &rect, const QColor &color) const
{
    QPen pen(color, 1.5, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin);
    painter->setPen(pen);
    painter->setBrush(Qt::NoBrush);
    const QPointF c = rect.center();
    const qreal h = 4.5; // половина значка

    switch (type()) {
    case DecorationButtonType::Minimize:
        painter->drawLine(QPointF(c.x() - h, c.y() + 0.5), QPointF(c.x() + h, c.y() + 0.5));
        break;
    case DecorationButtonType::Maximize:
        if (isChecked()) {
            // Два окна: вернуть прежний размер.
            painter->drawRoundedRect(QRectF(c.x() - h, c.y() - h + 2.5, 2 * h - 2.5, 2 * h - 2.5), 1.5, 1.5);
            QPainterPath back;
            back.moveTo(c.x() - h + 2.5, c.y() - h + 1);
            back.lineTo(c.x() - h + 2.5, c.y() - h);
            back.lineTo(c.x() + h, c.y() - h);
            back.lineTo(c.x() + h, c.y() + h - 2.5);
            back.lineTo(c.x() + h - 1, c.y() + h - 2.5);
            painter->drawPath(back);
        } else {
            painter->drawRoundedRect(QRectF(c.x() - h, c.y() - h, 2 * h, 2 * h), 2, 2);
        }
        break;
    case DecorationButtonType::Close:
        painter->drawLine(QPointF(c.x() - h + 0.5, c.y() - h + 0.5), QPointF(c.x() + h - 0.5, c.y() + h - 0.5));
        painter->drawLine(QPointF(c.x() + h - 0.5, c.y() - h + 0.5), QPointF(c.x() - h + 0.5, c.y() + h - 0.5));
        break;
    case DecorationButtonType::OnAllDesktops:
        painter->drawEllipse(c, h - 1, h - 1);
        if (isChecked()) {
            painter->setBrush(color);
            painter->drawEllipse(c, 1.5, 1.5);
        }
        break;
    case DecorationButtonType::KeepAbove:
    case DecorationButtonType::Shade:
        painter->drawPolyline(QList<QPointF>{{c.x() - h, c.y() + h / 2}, {c.x(), c.y() - h / 2}, {c.x() + h, c.y() + h / 2}});
        break;
    case DecorationButtonType::KeepBelow:
        painter->drawPolyline(QList<QPointF>{{c.x() - h, c.y() - h / 2}, {c.x(), c.y() + h / 2}, {c.x() + h, c.y() - h / 2}});
        break;
    case DecorationButtonType::ContextHelp: {
        QFont font = painter->font();
        font.setPixelSize(13);
        font.setBold(true);
        painter->setFont(font);
        painter->drawText(rect, Qt::AlignCenter, QStringLiteral("?"));
        break;
    }
    default:
        break;
    }
}

} // namespace Sedmio
