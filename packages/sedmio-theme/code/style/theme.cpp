#include "theme.h"

#include "themedata.h"

Theme::Theme(QObject *parent)
    : QQmlPropertyMap(this, parent)
{
    connect(Sedmio::ThemeData::instance(), &Sedmio::ThemeData::changed, this, &Theme::update);
    update();
}

void Theme::update()
{
    // Только изменившееся: каждая замена будит привязки в QML.
    const QVariantMap values = Sedmio::ThemeData::instance()->values();
    for (auto it = values.begin(); it != values.end(); ++it) {
        if (value(it.key()) != it.value())
            insert(it.key(), it.value());
    }
}
