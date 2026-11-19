#pragma once

#include <QObject>
#include <QVariantList>
#include <QtQml/qqmlregistration.h>

// Программы по умолчанию: чем открывать ссылки, почту, папки, музыку,
// видео, фото, PDF и текст. Выбор — в ~/.config/mimeapps.list поверх наших
// значений из /etc/xdg/mimeapps.list (sedmio-settings), через
// KApplicationTrader — так же, как модуль параметров KDE.
class Defaults : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    // [{id, title, apps: [{id, name, icon}], current (индекс или -1)}]
    Q_PROPERTY(QVariantList categories READ categories NOTIFY changed)

public:
    explicit Defaults(QObject *parent = nullptr);

    QVariantList categories() const { return m_categories; }

    Q_INVOKABLE void choose(const QString &category, const QString &appId);

Q_SIGNALS:
    void changed();

private:
    void load();

    QVariantList m_categories;
};
