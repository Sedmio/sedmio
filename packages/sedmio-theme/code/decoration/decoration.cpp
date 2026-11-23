#include "decoration.h"

#include "button.h"
#include "ownheader.h"
#include "shadow.h"
#include "themedata.h"

#include <KDecoration3/DecoratedWindow>
#include <KDecoration3/DecorationSettings>
#include <KPluginFactory>

#include <QFontMetricsF>
#include <QPainter>
#include <QPainterPath>
#include <QTimer>

K_PLUGIN_FACTORY_WITH_JSON(SedmioDecorationFactory, "sedmio.json", registerPlugin<Sedmio::Decoration>();)

namespace Sedmio
{
namespace
{
// Невидимое поле за краем окна, за которое тянут размер.
constexpr qreal resizeMargin = 6;
// Отступ кнопок от краёв заголовка и между ними.
constexpr qreal sideMargin = 6;
constexpr qreal buttonSpacing = 2;
// Тень активного и остальных окон.
constexpr qreal activeShadow = 0.34;
constexpr qreal inactiveShadow = 0.18;
} // namespace

Decoration::Decoration(QObject *parent, const QVariantList &args)
    : KDecoration3::Decoration(parent, args)
{
}

Decoration::~Decoration() = default;

bool Decoration::init()
{
    KDecoration3::DecoratedWindow *w = window();
    const auto repaint = [this] {
        update();
    };

    connect(ThemeData::instance(), &ThemeData::changed, this, [this] {
        updateLayout();
        updateShadow();
        update();
    });
    connect(w, &KDecoration3::DecoratedWindow::activeChanged, this, [this] {
        updateShadow();
        update();
    });
    // app_id и «модальное» приходят от программы — могли прийти и после
    // рамки; заодно перепроверить, чей заголовок.
    connect(w, &KDecoration3::DecoratedWindow::captionChanged, this, &Decoration::updateLayout);
    connect(w, &KDecoration3::DecoratedWindow::maximizeableChanged, this, &Decoration::updateLayout);
    connect(w, &KDecoration3::DecoratedWindow::iconChanged, this, repaint);
    connect(w, &KDecoration3::DecoratedWindow::widthChanged, this, &Decoration::updateLayout);
    connect(w, &KDecoration3::DecoratedWindow::maximizedChanged, this, [this] {
        updateLayout();
        updateShadow();
    });
    connect(w, &KDecoration3::DecoratedWindow::adjacentScreenEdgesChanged, this, &Decoration::updateLayout);

    // Кнопки по новому списку из настроек группы пересоздают сами — только
    // расставить заново (как Breeze, после них).
    const auto s = settings();
    connect(s.get(), &KDecoration3::DecorationSettings::decorationButtonsLeftChanged, this, &Decoration::updateButtonsGeometryLater);
    connect(s.get(), &KDecoration3::DecorationSettings::decorationButtonsRightChanged, this, &Decoration::updateButtonsGeometryLater);
    connect(s.get(), &KDecoration3::DecorationSettings::reconfigured, this, repaint);

    createButtons();
    updateLayout();
    updateShadow();
    return true;
}

bool Decoration::isActive() const
{
    return window()->isActive();
}

bool Decoration::isMaximized() const
{
    return window()->isMaximized();
}

qreal Decoration::titleHeight() const
{
    if (m_ownHeader)
        return 0;
    return std::clamp(ThemeData::instance()->number(QStringLiteral("titleHeight")), 24.0, 64.0);
}

qreal Decoration::cornerRadius() const
{
    if (isMaximized())
        return 0;
    return std::clamp(ThemeData::instance()->number(QStringLiteral("windowRadius")), 0.0, 32.0);
}

QColor Decoration::themeColor(const QString &key) const
{
    return ThemeData::instance()->color(key);
}

void Decoration::createButtons()
{
    m_left = new KDecoration3::DecorationButtonGroup(KDecoration3::DecorationButtonGroup::Position::Left, this, &Button::create);
    m_right = new KDecoration3::DecorationButtonGroup(KDecoration3::DecorationButtonGroup::Position::Right, this, &Button::create);
    m_left->setSpacing(buttonSpacing);
    m_right->setSpacing(buttonSpacing);
    // Группа считает себя от левого края: кнопка справа пропала или
    // появилась (окно перестало разворачиваться, второй рабочий стол) —
    // прижать группу к правому краю заново.
    connect(m_right, &KDecoration3::DecorationButtonGroup::geometryChanged, this, &Decoration::updateButtonsGeometryLater);
    updateButtonsGeometry();
    update();
}

void Decoration::updateButtonsGeometryLater()
{
    // Не сразу: расстановка меняет геометрию группы, а та снова зовёт сюда.
    if (m_buttonsPending)
        return;
    m_buttonsPending = true;
    QTimer::singleShot(0, this, [this] {
        m_buttonsPending = false;
        updateButtonsGeometry();
        update();
    });
}

void Decoration::updateLayout()
{
    // Диалоги (модальные, постоянного размера) — с нашим заголовком: свои
    // кнопки окна есть только у главных окон.
    const KDecoration3::DecoratedWindow *w = window();
    m_ownHeader = drawsOwnHeader(w->windowClass()) && !w->isModal() && w->isMaximizeable();

    const qreal title = titleHeight();
    setBorders(QMarginsF(0, title, 0, 0));
    const qreal margin = isMaximized() ? 0 : resizeMargin;
    setResizeOnlyBorders(QMarginsF(margin, margin, margin, margin));
    setTitleBar(m_ownHeader ? QRectF() : QRectF(0, 0, window()->width(), title));

    const qreal radius = cornerRadius();
    setBorderRadius(KDecoration3::BorderRadius(radius));
    setBorderOutline(KDecoration3::BorderOutline(isMaximized() ? 0 : 1, themeColor(QStringLiteral("windowOutline")),
                                                 KDecoration3::BorderRadius(radius)));
    // Развёрнутое окно непрозрачно, если заголовок без прозрачности (тема
    // может дать #AARRGGBB) — иначе под ним остался бы мусор.
    setOpaque(!m_ownHeader && isMaximized() && themeColor(QStringLiteral("windowTitle")).alpha() == 255
              && themeColor(QStringLiteral("windowTitleInactive")).alpha() == 255);

    updateButtonsGeometry();
    update();
}

void Decoration::updateButtonsGeometry()
{
    if (!m_left || !m_right)
        return;
    const qreal title = titleHeight();
    // Без полосы заголовка кнопок нет (свои — у программы).
    const qreal size = m_ownHeader ? 0 : title - 8;
    for (KDecoration3::DecorationButton *button : m_left->buttons() + m_right->buttons())
        button->setGeometry(QRectF(0, 0, size, size));
    const qreal top = (title - size) / 2;
    m_left->setPos(QPointF(sideMargin, top));
    m_right->setPos(QPointF(window()->width() - m_right->geometry().width() - sideMargin, top));
}

void Decoration::updateShadow()
{
    setShadow(windowShadow(themeColor(QStringLiteral("shadow")), isActive() ? activeShadow : inactiveShadow,
                           std::clamp(ThemeData::instance()->number(QStringLiteral("windowRadius")), 0.0, 32.0)));
}

void Decoration::paint(QPainter *painter, const QRectF &repaintArea)
{
    // Рисовать нечего: контур — KWin (setBorderOutline), остальное — программа.
    if (m_ownHeader)
        return;

    const qreal width = window()->width();
    const qreal title = titleHeight();
    const qreal radius = cornerRadius();

    painter->save();
    painter->setRenderHint(QPainter::Antialiasing);

    // Заголовок; верхние углы скруглены, нижние — край окна программы.
    QPainterPath path;
    path.moveTo(0, title);
    path.lineTo(0, radius);
    path.arcTo(QRectF(0, 0, 2 * radius, 2 * radius), 180, -90);
    path.lineTo(width - radius, 0);
    path.arcTo(QRectF(width - 2 * radius, 0, 2 * radius, 2 * radius), 90, -90);
    path.lineTo(width, title);
    path.closeSubpath();
    painter->fillPath(path, themeColor(isActive() ? QStringLiteral("windowTitle") : QStringLiteral("windowTitleInactive")));

    // Линия по низу заголовка: видно, где кончается заголовок и начинается
    // программа (у многих программ фон того же цвета, что и заголовок).
    painter->save();
    painter->setRenderHint(QPainter::Antialiasing, false);
    painter->fillRect(QRectF(0, title - 1, width, 1), themeColor(QStringLiteral("lineStrong")));
    painter->restore();

    // Название — посередине окна, а если не помещается — между кнопками.
    QFont font = settings()->font();
    // Шрифт темы — одно имя или список запасных через запятую.
    QStringList families;
    for (const QString &family : ThemeData::instance()->string(QStringLiteral("fontFamily")).split(QLatin1Char(','))) {
        if (!family.trimmed().isEmpty())
            families << family.trimmed();
    }
    if (!families.isEmpty())
        font.setFamilies(families);
    font.setPixelSize(13);
    font.setWeight(QFont::DemiBold);
    font.setVariableAxis(QFont::Tag("wght"), 600);
    painter->setFont(font);
    const QFontMetricsF metrics(font);

    const qreal left = (m_left && !m_left->buttons().isEmpty() ? m_left->geometry().right() : 0) + 10;
    const qreal right = (m_right && !m_right->buttons().isEmpty() ? m_right->geometry().left() : width) - 10;
    if (right > left) {
        const QString caption = metrics.elidedText(window()->caption(), Qt::ElideRight, right - left);
        const qreal textWidth = metrics.horizontalAdvance(caption);
        const qreal x = std::clamp((width - textWidth) / 2, left, std::max(left, right - textWidth));
        painter->setPen(themeColor(isActive() ? QStringLiteral("ink") : QStringLiteral("inkMuted")));
        painter->drawText(QRectF(x, 0, textWidth + 1, title), Qt::AlignVCenter | Qt::AlignLeft | Qt::TextSingleLine, caption);
    }

    if (m_left)
        m_left->paint(painter, repaintArea);
    if (m_right)
        m_right->paint(painter, repaintArea);
    painter->restore();
}

} // namespace Sedmio

#include "decoration.moc"
