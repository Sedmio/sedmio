#pragma once

#include <QFileSystemWatcher>
#include <QHash>
#include <QObject>
#include <QTimer>
#include <QVariantList>
#include <QtQml/qqmlregistration.h>

#include "keyedmodel.h"

// «Модули»: части системы, которые можно выключить, — модули оболочки
// (/usr/share/sedmio/shell/modules, пакет sedmio-shell). Список и
// переключение — через sedmio-modules (list --json, on, off), чтобы
// правила были в одном месте: он же включает скрипты KWin модуля и
// просит оболочку перечитать выбор.
class Modules : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    // [{name, model}] — разделы по порядку; model — KeyedModel строк
    // {id, name, description, icon, group, enabled, default}. Список
    // разделов меняется, только когда меняются сами разделы: строки
    // обновляются в своих моделях на месте.
    Q_PROPERTY(QVariantList groups READ groups NOTIFY groupsChanged)
    Q_PROPERTY(QString message READ message NOTIFY messageChanged)

public:
    explicit Modules(QObject *parent = nullptr);

    QVariantList groups() const { return m_groups; }
    QString message() const { return m_message; }

    Q_INVOKABLE void setEnabled(const QString &id, bool enabled);

Q_SIGNALS:
    void groupsChanged();
    void messageChanged();

private:
    void load();
    void run(const QStringList &args);
    void setMessage(const QString &message);
    void watch();

    QFileSystemWatcher m_watcher;
    QTimer m_reload;
    QVariantList m_groups;
    QStringList m_groupNames;
    QHash<QString, KeyedModel *> m_models;
    QString m_message;
};
