#pragma once

#include <QFileSystemWatcher>
#include <QObject>
#include <QTimer>
#include <QVariantList>
#include <QtQml/qqmlregistration.h>

#include "keyedmodel.h"

// «Автозапуск»: программы, которые открываются сами при входе, — записи
// ~/.config/autostart/*.desktop (их пишут и сами программы: Steam,
// Discord, Telegram). Выключить — Hidden=true в той же записи (так делает
// и модуль KDE; запуск при входе — systemd-xdg-autostart-generator,
// он это понимает), убрать — удалить запись, добавить — копия .desktop
// программы. Системные службы (/etc/xdg/autostart) не показываем.
class Autostart : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    // [{file, name, icon, enabled, missing}]
    Q_PROPERTY(QVariantList entries READ entries NOTIFY changed)
    // То же моделью — для Repeater (строки не пересоздаются, когда
    // программа переписывает свою запись).
    Q_PROPERTY(KeyedModel *entryModel READ entryModel CONSTANT)
    // Что можно добавить: [{id, name, icon, search}] — программы из меню, которых
    // ещё нет в автозапуске.
    Q_PROPERTY(QVariantList apps READ apps NOTIFY changed)
    Q_PROPERTY(QString message READ message NOTIFY changed)

public:
    explicit Autostart(QObject *parent = nullptr);

    QVariantList entries() const { return m_entries; }
    KeyedModel *entryModel() const { return m_entryModel; }
    QVariantList apps() const { return m_apps; }
    QString message() const { return m_message; }

    Q_INVOKABLE void setEnabled(const QString &file, bool enabled);
    Q_INVOKABLE void remove(const QString &file);
    Q_INVOKABLE void add(const QString &appId);

Q_SIGNALS:
    void changed();

private:
    void load();
    QString directory() const;

    QFileSystemWatcher m_watcher;
    QTimer m_reload;
    QVariantList m_entries;
    KeyedModel *m_entryModel;
    QVariantList m_apps;
    QString m_message;
};
