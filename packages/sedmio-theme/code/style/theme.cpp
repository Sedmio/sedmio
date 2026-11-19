#include "theme.h"

#include "themedata.h"

#include <QCoreApplication>
#include <QEvent>

Theme::Theme(QObject *parent)
    : QQmlPropertyMap(this, parent)
{
    connect(Sedmio::ThemeData::instance(), &Sedmio::ThemeData::changed, this, &Theme::update);
    update();
    insert(QStringLiteral("paletteSerial"), m_paletteSerial);
    if (QCoreApplication::instance())
        QCoreApplication::instance()->installEventFilter(this);
}

bool Theme::eventFilter(QObject *watched, QEvent *event)
{
    if (event->type() == QEvent::ApplicationPaletteChange && watched == QCoreApplication::instance())
        insert(QStringLiteral("paletteSerial"), ++m_paletteSerial);
    return QQmlPropertyMap::eventFilter(watched, event);
}

void Theme::update()
{
    // Только изменившееся: каждая замена будит привязки в QML.
    const QVariantMap values = Sedmio::ThemeData::instance()->values();
    for (auto it = values.begin(); it != values.end(); ++it) {
        if (value(it.key()) != it.value())
            insert(it.key(), it.value());
    }
    // Ключа нет в новой теме — не оставлять значение прежней.
    for (const QString &key : keys()) {
        if (!values.contains(key) && key != QLatin1String("paletteSerial") && value(key).isValid())
            clear(key);
    }
}
