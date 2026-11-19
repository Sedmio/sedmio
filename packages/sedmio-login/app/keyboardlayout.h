#pragma once

#include <QObject>
#include <QVariantList>
#include <qqmlregistration.h>

// Раскладки клавиатуры, их держит KWin (org.kde.keyboard /Layouts): список,
// текущая, «следующая». Как KeyboardLayout из plasma-workspace.
class KeyboardLayout : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(int layout READ layout WRITE setLayout NOTIFY layoutChanged)
    // [{shortName, displayName, longName}]
    Q_PROPERTY(QVariantList layoutsList READ layoutsList NOTIFY layoutsListChanged)

public:
    explicit KeyboardLayout(QObject *parent = nullptr);

    int layout() const;
    void setLayout(int layout);
    QVariantList layoutsList() const;

    Q_INVOKABLE void switchToNextLayout();
    Q_INVOKABLE void switchToPreviousLayout();

Q_SIGNALS:
    void layoutChanged();
    void layoutsListChanged();

private Q_SLOTS:
    void onLayoutChanged(uint index);
    void readLayouts();

private:
    void readLayout();

    int m_layout = 0;
    QVariantList m_layouts;
};
