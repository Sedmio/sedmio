#pragma once

#include <QObject>
#include <QPointer>
#include <QVariantMap>
#include <QWindow>
#include <QtQml/qqmlregistration.h>

#include <functional>

class QQmlEngine;
class QJSEngine;

// Вопросы, которые задания KIO задают по ходу работы: «файл уже есть»,
// «не получилось скопировать — пропустить?», «чем открыть?». KIO сам
// показал бы для этого окна на QtWidgets; мы подставляем свои обработчики
// (install()), а окно с вопросом — PromptWindow.qml.
//
// Вопросы идут по очереди: два задания спросили одновременно — второй
// вопрос появится после ответа на первый.
class Prompts : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    // Текущий вопрос: {kind: "conflict" | "skip" | "openWith", …}; пустой — вопросов нет.
    Q_PROPERTY(QVariantMap current READ current NOTIFY currentChanged)
    // Над каким окном показывать вопрос.
    Q_PROPERTY(QWindow *parentWindow READ parentWindow NOTIFY currentChanged)

public:
    using Reply = std::function<void(const QVariantMap &answer)>;

    static Prompts *instance();
    static Prompts *create(QQmlEngine *, QJSEngine *);

    // Подменить окна KIO на наши — для всех заданий этой программы.
    static void install();

    QVariantMap current() const;
    QWindow *parentWindow() const { return m_parentWindow; }

    // Задать вопрос от имени owner (обработчик задания). Если owner
    // исчезнет раньше ответа (задание отменили из оболочки), вопрос снимется.
    void ask(QObject *owner, const QVariantMap &question, const Reply &reply);

    // Ответ на текущий вопрос.
    Q_INVOKABLE void answer(const QVariantMap &answer);

    // Все программы для «Открыть с помощью»: [{id, name, icon, comment}].
    Q_INVOKABLE QVariantList allApplications() const;
    // Одна программа по имени файла .desktop (с «.desktop» или без);
    // нет такой — пусто.
    static QVariantMap applicationInfo(const QString &desktopId);

Q_SIGNALS:
    void currentChanged();

private:
    // Один на программу: instance(); QML получает его же через create().
    explicit Prompts(QObject *parent);

    struct Pending {
        QPointer<QObject> owner;
        QVariantMap question;
        Reply reply;
    };
    void ownerDestroyed();
    void showFirst();

    QList<Pending> m_queue;
    QPointer<QWindow> m_parentWindow;
};
