#pragma once

#include <QFileSystemWatcher>
#include <QObject>
#include <QVariantList>
#include <QtQml/qqmlregistration.h>

// Темы Sedmio: какие установлены и выбор. Темы — каталоги
// sedmio/themes/<тема>/theme.json (свои в ~/.local/share перекрывают
// системные с тем же именем); выбор — первая строка ~/.config/sedmio/theme.
// Его читают все наши программы (модуль Sedmio.Style), рамки окон и служба
// цветов чужих программ — тема меняется везде сразу. Какая тема сейчас
// действует — Theme.themeId (битая выбранная — вместо неё «sedmio»).
class Themes : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    // [{id, name, description, user, colors: {paper, ink, ...}}] — по имени;
    // цвета, которых в теме нет, — из темы sedmio (её же подложит модуль).
    Q_PROPERTY(QVariantList themes READ themes NOTIFY themesChanged)
    Q_PROPERTY(QString error READ error NOTIFY errorChanged)

public:
    explicit Themes(QObject *parent = nullptr);

    QVariantList themes() const { return m_themes; }
    QString error() const { return m_error; }

    Q_INVOKABLE void choose(const QString &id);
    Q_INVOKABLE void rescan();

Q_SIGNALS:
    void themesChanged();
    void errorChanged();

private:
    void setError(const QString &error);

    QVariantList m_themes;
    QString m_error;
    QFileSystemWatcher m_watcher;
};
