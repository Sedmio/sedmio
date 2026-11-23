#pragma once

#include <KDecoration3/Decoration>
#include <KDecoration3/DecorationButtonGroup>

#include <QVariantList>

namespace Sedmio
{

// Рамка окна: заголовок цвета темы с названием посередине, значок
// программы слева (меню окна), кнопки справа, скруглённые углы, тонкий
// контур и тень. Боковых рамок нет — тянуть за край можно и так
// (невидимое поле). Всё из темы (Sedmio::ThemeData): тема поменялась —
// рамки перерисовываются на ходу.
class Decoration : public KDecoration3::Decoration
{
    Q_OBJECT

public:
    explicit Decoration(QObject *parent = nullptr, const QVariantList &args = {});
    ~Decoration() override;

    bool init() override;
    void paint(QPainter *painter, const QRectF &repaintArea) override;

    bool isActive() const;
    // Развёрнуто на весь экран: без скругления и полей.
    bool isMaximized() const;
    // Полоса заголовка — наша; 0, если заголовок рисует программа.
    qreal titleHeight() const;
    bool ownHeader() const { return m_ownHeader; }
    qreal cornerRadius() const;
    QColor themeColor(const QString &key) const;

private:
    void createButtons();
    void updateLayout();
    void updateButtonsGeometry();
    void updateButtonsGeometryLater();
    void updateShadow();

    KDecoration3::DecorationButtonGroup *m_left = nullptr;
    KDecoration3::DecorationButtonGroup *m_right = nullptr;
    bool m_buttonsPending = false;
    bool m_ownHeader = false;
};

} // namespace Sedmio
