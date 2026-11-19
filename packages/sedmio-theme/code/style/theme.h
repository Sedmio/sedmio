#pragma once

#include <QQmlPropertyMap>
#include <QtQml/qqmlregistration.h>

// Тема Sedmio для всех наших программ: import Sedmio.Style, дальше
// Theme.paper, Theme.radius, Theme.animFast... Значения — из
// Sedmio::ThemeData (common/themedata.h: откуда берётся тема и что будет,
// если файл битый). Тема поменялась — привязки в QML обновляются сами.
//
// Ещё Theme.paletteSerial — счётчик смен палитры программы (её пишет из
// темы sedmio-theme-sync, а KDE перекрашивает по ней значки): прибавить к
// адресу значка, и он перезапросится уже в новых цветах.
class Theme : public QQmlPropertyMap
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

public:
    explicit Theme(QObject *parent = nullptr);

protected:
    bool eventFilter(QObject *watched, QEvent *event) override;

private:
    void update();
    int m_paletteSerial = 0;
};
