#pragma once

#include <QQmlPropertyMap>
#include <QtQml/qqmlregistration.h>

// Тема Sedmio для всех наших программ: import Sedmio.Style, дальше
// Theme.paper, Theme.radius, Theme.animFast... Значения — из
// Sedmio::ThemeData (common/themedata.h: откуда берётся тема и что будет,
// если файл битый). Тема поменялась — привязки в QML обновляются сами.
class Theme : public QQmlPropertyMap
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

public:
    explicit Theme(QObject *parent = nullptr);

private:
    void update();
};
