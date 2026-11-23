#pragma once

#include <QColor>
#include <QHash>
#include <QObject>
#include <QtQml/qqmlregistration.h>

// Однотонные символы (Lucide) вместо цветных значков темы: для кнопок,
// меню и боковых панелей. Имена — как у значков freedesktop
// (/usr/share/sedmio/symbols/names.json сопоставляет их файлам); чего в
// списке нет — has() == false, рисовать значок темы как раньше.
//
//   Image { source: Symbols.url("go-home", Theme.inkSoft, 20) }
//
// url — картинка data: с уже вписанным цветом и толщиной линии под размер
// (линия ~1,5 пикселя при любом размере, как у кнопок рамки окна).
class Symbols : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

public:
    explicit Symbols(QObject *parent = nullptr);

    Q_INVOKABLE bool has(const QString &name) const;
    Q_INVOKABLE QString url(const QString &name, const QColor &color, qreal size) const;

private:
    QString fileFor(const QString &name) const;

    QString m_dir;
    QHash<QString, QString> m_names;
    mutable QHash<QString, QByteArray> m_svg;
};
