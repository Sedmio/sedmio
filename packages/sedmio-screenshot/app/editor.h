#pragma once

#include <QObject>
#include <QString>
#include <QUrl>
#include <QVariant>
#include <QtQml/qqmlregistration.h>

// Файл, который правят в редакторе снимков, и что с готовой картинкой
// делать: сохранить, скопировать в буфер обмена. Картинку рисует
// EditorWindow.qml (grabToImage) — сюда приходит готовый QImage.
class Editor : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    // Полный путь к файлу; «Сохранить как» его меняет.
    Q_PROPERTY(QString path READ path NOTIFY pathChanged)
    Q_PROPERTY(QString fileName READ fileName NOTIFY pathChanged)
    Q_PROPERTY(QString folder READ folder NOTIFY pathChanged)
    // Снимок, каким его открыли: пометки рисуются поверх, сам он не
    // меняется (и после «Сохранить» не перечитывается).
    Q_PROPERTY(QUrl sourceUrl READ sourceUrl CONSTANT)

public:
    explicit Editor(QObject *parent = nullptr);

    static void setStartPath(const QString &path);

    QString path() const { return m_path; }
    QString fileName() const;
    QString folder() const;
    QUrl sourceUrl() const { return m_source; }

    // Сохранить картинку (QImage из ItemGrabResult.image). target — путь
    // или file:// адрес; пусто — в тот же файл. Формат — по расширению.
    Q_INVOKABLE bool save(const QVariant &image, const QString &target = QString());
    // В буфер обмена через wl-copy: картинка остаётся в буфере и после
    // закрытия редактора.
    Q_INVOKABLE bool copy(const QVariant &image);
    // Открыть папку файла (xdg-open).
    Q_INVOKABLE void openFolder() const;

Q_SIGNALS:
    void pathChanged();

private:
    QString m_path;
    QUrl m_source;
};
