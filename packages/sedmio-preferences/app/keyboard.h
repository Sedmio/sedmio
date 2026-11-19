#pragma once

#include <QObject>
#include <QVariantList>
#include <QtQml/qqmlregistration.h>

// Раскладки клавиатуры: какие есть, в каком порядке, чем переключаются.
// Хранятся там же, где у KDE, — ~/.config/kxkbrc; запись с флагом Notify,
// по нему KWin перечитывает раскладки (как от модуля параметров KDE).
// Правки применяются сразу: ошибиться тут нельзя — последнюю раскладку
// не удалить.
class Keyboard : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    // [{layout, variant, name, short}] — в порядке переключения.
    Q_PROPERTY(QVariantList layouts READ layouts NOTIFY changed)
    // alt_shift, ctrl_shift, win_space, caps — или "" (только мышью).
    Q_PROPERTY(QString switchKey READ switchKey NOTIFY changed)
    // У каждого окна своя раскладка (как в Windows) или одна на всех.
    Q_PROPERTY(bool perWindow READ perWindow NOTIFY changed)
    Q_PROPERTY(QString error READ error NOTIFY changed)

public:
    explicit Keyboard(QObject *parent = nullptr);

    QVariantList layouts() const;
    QString switchKey() const { return m_switchKey; }
    bool perWindow() const { return m_perWindow; }
    QString error() const { return m_error; }

    // [{layout, name, search}] — все раскладки xkb (без вариантов), по имени.
    Q_INVOKABLE QVariantList available() const;
    Q_INVOKABLE void add(const QString &layout);
    Q_INVOKABLE void remove(int index);
    Q_INVOKABLE void move(int index, int step);
    Q_INVOKABLE void setSwitchKey(const QString &key);
    Q_INVOKABLE void setPerWindow(bool perWindow);

Q_SIGNALS:
    void changed();

private:
    struct Layout {
        QString layout;
        QString variant;
    };

    void load();
    void save();

    QList<Layout> m_layouts;
    QStringList m_otherOptions; // параметры xkb, кроме переключения, — не трогаем
    QString m_switchKey;
    bool m_perWindow = true;
    QString m_error;
};
