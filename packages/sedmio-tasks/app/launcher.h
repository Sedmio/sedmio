#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QVariantList>

// «Запустить новую задачу» (как в диспетчере задач Windows): программа по
// названию или команда. Замена KRunner на случай, когда оболочки (и её
// меню программ) нет. Запуск — в своей группе systemd, как у оболочки
// (/usr/lib/sedmio/launch): программа переживает и оболочку, и диспетчер.
class Launcher : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    // Что не получилось при последнем запуске («Не найдено: foo»).
    Q_PROPERTY(QString error READ error NOTIFY errorChanged)

public:
    explicit Launcher(QObject *parent = nullptr);

    QString error() const { return m_error; }

    // Программы, подходящие к запросу: [{id, name, comment, icon}], до 6.
    Q_INVOKABLE QVariantList search(const QString &query) const;
    // Запустить программу по id (.desktop). true — запущена.
    Q_INVOKABLE bool launchApp(const QString &id);
    // Запустить строку как команду.
    Q_INVOKABLE bool runCommand(const QString &command);
    Q_INVOKABLE void clearError() { setError({}); }

Q_SIGNALS:
    void errorChanged();

private:
    bool start(const QString &id, const QStringList &argv, const QString &workingDirectory = {});
    void setError(const QString &error);

    QString m_error;
};
