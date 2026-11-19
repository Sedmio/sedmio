#pragma once

#include <KScreen/Config>

#include <QObject>
#include <QTimer>
#include <QVariantList>
#include <QtQml/qqmlregistration.h>

// Экраны для страницы «Экран»: что подключено и как настроено (libkscreen —
// тот же движок, что у параметров KDE; применяет KWin, он же запоминает).
//
// Правки копятся в черновике и применяются кнопкой «Применить». После
// применения — 15 секунд на подтверждение, как в Windows: не подтвердили
// (картинки нет, окно не видно) — возвращаем прежние параметры сами.
// Закрыли «Параметры», не подтвердив, — тоже возвращаем.
class Displays : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    // [{id, title, connector, builtin, enabled, primary, x, y, width, height,
    //   resolutions: [{width, height, label}], resolution (индекс),
    //   rates: [{rate, label}], rate (индекс), scale, rotation}]
    // Геометрия — в логических пикселях, как раскладывает KWin.
    Q_PROPERTY(QVariantList outputs READ outputs NOTIFY changed)
    Q_PROPERTY(bool ready READ ready NOTIFY changed)
    // Черновик отличается от того, что сейчас на экранах.
    Q_PROPERTY(bool dirty READ dirty NOTIFY changed)
    // Применили и ждём подтверждения: сколько секунд осталось, 0 — не ждём.
    Q_PROPERTY(int revertIn READ revertIn NOTIFY revertInChanged)
    Q_PROPERTY(QString error READ error NOTIFY changed)

public:
    explicit Displays(QObject *parent = nullptr);
    ~Displays() override;

    QVariantList outputs() const;
    bool ready() const { return bool(m_draft); }
    bool dirty() const { return m_dirty; }
    int revertIn() const { return m_revertIn; }
    QString error() const { return m_error; }

    Q_INVOKABLE void setResolution(int outputId, int index);
    Q_INVOKABLE void setRate(int outputId, int index);
    Q_INVOKABLE void setScale(int outputId, double scale);
    Q_INVOKABLE void setRotation(int outputId, int rotation);
    Q_INVOKABLE void setEnabled(int outputId, bool enabled);
    Q_INVOKABLE void setPrimary(int outputId);
    // Поставить экран левее/правее соседа (порядок слева направо).
    Q_INVOKABLE void move(int outputId, int step);

    Q_INVOKABLE void apply();
    Q_INVOKABLE void confirm();
    Q_INVOKABLE void revert();
    // Отменить несохранённые правки черновика.
    Q_INVOKABLE void discard();

Q_SIGNALS:
    void changed();
    void revertInChanged();

private:
    void load();
    void onConfigChanged();
    void setConfig(const KScreen::ConfigPtr &config);
    void edited();
    void layoutRow();
    void send(const KScreen::ConfigPtr &config);

    KScreen::ConfigPtr m_current;  // то, что сейчас на экранах
    KScreen::ConfigPtr m_draft;    // правки пользователя
    KScreen::ConfigPtr m_previous; // до «Применить» — для отката
    bool m_dirty = false;
    int m_revertIn = 0;
    QTimer m_countdown;
    QString m_error;
};
