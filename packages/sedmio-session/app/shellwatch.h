#pragma once

#include <QDBusObjectPath>
#include <QObject>
#include <QPointer>
#include <QQmlEngine>
#include <QQuickWindow>
#include <QTimer>
#include <QVariantMap>

// Аварийный режим вместо запасной оболочки Plasma: оболочка Sedmio
// (sedmio-shell.service) упала насовсем — systemd исчерпал перезапуски, —
// и сверху главного монитора появляется плашка: что случилось, чем
// пользоваться без панели (Alt+Tab; Ctrl+Shift+Esc — диспетчер задач, в нём
// «Запустить новую задачу») и кнопка «Перезапустить». Оболочка снова
// работает — плашка уходит.
// Живёт в sedmio-session-manager: он от оболочки не зависит.
class ShellWatch : public QObject
{
    Q_OBJECT

public:
    explicit ShellWatch(QObject *parent = nullptr);

    Q_INVOKABLE void restart();
    Q_INVOKABLE void dismiss();

private Q_SLOTS:
    void propertiesChanged(const QString &interface, const QVariantMap &changed, const QStringList &invalidated);

private:
    void watch();
    static bool isFailed(const QString &activeState, const QString &subState);
    bool currentlyFailed() const;
    void update(bool failed);
    void showBanner();
    void hideBanner();

    QQmlEngine m_engine;
    QPointer<QQuickWindow> m_banner;
    QString m_unitPath;
    QTimer m_confirm;
    bool m_failed = false;
};
