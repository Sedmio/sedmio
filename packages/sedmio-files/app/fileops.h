#pragma once

#include <QObject>
#include <QUrl>
#include <QVariantList>
#include <QtQml/qqmlregistration.h>

class KJob;

// Всё, что делается с файлами: открыть, копировать и вставить, в корзину,
// переименовать, создать папку, отменить. Работу делает KIO, так что ход
// долгих операций сам попадает в индикатор оболочки (сервер заданий).
class FileOps : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    // В буфере обмена есть файлы, которые можно вставить.
    Q_PROPERTY(bool canPaste READ canPaste NOTIFY clipboardChanged)
    // Адреса файлов в буфере, если их туда положили «Вырезать».
    Q_PROPERTY(QList<QUrl> cutUrls READ cutUrls NOTIFY clipboardChanged)
    Q_PROPERTY(bool canUndo READ canUndo NOTIFY undoChanged)
    Q_PROPERTY(QString undoText READ undoText NOTIFY undoChanged)
    Q_PROPERTY(QUrl homeUrl READ homeUrl CONSTANT)

public:
    explicit FileOps(QObject *parent = nullptr);

    bool canPaste() const;
    QList<QUrl> cutUrls() const;
    bool canUndo() const;
    QString undoText() const;
    QUrl homeUrl() const;

    // Открыть файл программой по умолчанию.
    Q_INVOKABLE void open(const QUrl &url);
    // Программы, которые открывают этот тип: [{id, name, icon}].
    Q_INVOKABLE QVariantList applications(const QString &mimeType) const;
    // Открыть программой; пустой id — выбрать программу в окне.
    Q_INVOKABLE void openWith(const QList<QUrl> &urls, const QString &serviceId);

    Q_INVOKABLE void copy(const QList<QUrl> &urls);
    Q_INVOKABLE void cut(const QList<QUrl> &urls);
    Q_INVOKABLE void paste(const QUrl &destination);
    // Перетащили сюда: копировать или переносить.
    Q_INVOKABLE void drop(const QList<QUrl> &urls, const QUrl &destination, bool move);
    // Переносить ли по умолчанию: тот же диск — переносим, другой — копируем.
    Q_INVOKABLE bool sameDevice(const QList<QUrl> &urls, const QUrl &destination) const;

    Q_INVOKABLE void trash(const QList<QUrl> &urls);
    Q_INVOKABLE void remove(const QList<QUrl> &urls);
    Q_INVOKABLE void restore(const QList<QUrl> &urls);
    Q_INVOKABLE void emptyTrash();

    // Переименовать; пустая строка — получилось начать, иначе почему нельзя.
    Q_INVOKABLE QString rename(const QUrl &url, const QString &newName);
    // Создать папку; вернёт имя (с номером, если такое уже есть).
    Q_INVOKABLE QString createFolder(const QUrl &directory, const QString &name);
    Q_INVOKABLE void undo();
    // Положить текст в буфер обмена (например, путь к файлу).
    Q_INVOKABLE void copyText(const QString &text);
    // Положить в буфер пути файлов текстом, по одному в строке.
    Q_INVOKABLE void copyPaths(const QList<QUrl> &urls);

    // Путь для показа: /home/user/Фото → ~/Фото.
    Q_INVOKABLE QString prettyPath(const QUrl &url) const;
    Q_INVOKABLE QString formatSize(qreal bytes) const;
    // Части пути для строки адреса: [{name, url}], от корня (или от
    // домашней папки) до этой папки.
    Q_INVOKABLE QVariantList crumbs(const QUrl &url) const;
    // Что ввели в строку адреса («~/Фото», «/tmp», «smb://…») → адрес.
    Q_INVOKABLE QUrl urlFromInput(const QString &text) const;

Q_SIGNALS:
    void clipboardChanged();
    void undoChanged();
    // Операция не удалась (отмену пользователем не сообщаем).
    void error(const QString &message);
    // В корзину не убрать — можно предложить удалить насовсем.
    void trashUnavailable(const QList<QUrl> &urls, const QString &reason);

private:
    void watch(KJob *job);
    void putOnClipboard(const QList<QUrl> &urls, bool cut);
};
