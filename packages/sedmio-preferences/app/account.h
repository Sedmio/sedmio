#pragma once

#include <QFileSystemWatcher>
#include <QObject>
#include <QQmlEngine>
#include <QUrl>

class QTemporaryFile;

// «Учётная запись»: имя, картинка, пароль — через AccountsService (её же
// читают экран входа и экран блокировки); вход без пароля — секция
// [initial_session] в /etc/greetd/sedmio.toml через pkexec
// /usr/lib/sedmio/set-autologin (пакет sedmio-login).
class Account : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(bool ready READ ready NOTIFY changed)
    Q_PROPERTY(QString userName READ userName NOTIFY changed)
    Q_PROPERTY(QString realName READ realName NOTIFY changed)
    // file:// с номером версии: та же картинка по тому же пути после смены.
    Q_PROPERTY(QUrl avatar READ avatar NOTIFY changed)
    // Вход без пароля: включён для нас; включён для другого (имя); можно ли менять.
    Q_PROPERTY(bool autologin READ autologin NOTIFY changed)
    Q_PROPERTY(QString autologinOther READ autologinOther NOTIFY changed)
    Q_PROPERTY(bool autologinAvailable READ autologinAvailable CONSTANT)
    // Идёт запрос (ждём пароль в окне polkit и т. п.).
    Q_PROPERTY(bool busy READ busy NOTIFY changed)
    // Итог последнего действия: сообщение и ошибка ли это.
    Q_PROPERTY(QString message READ message NOTIFY changed)
    Q_PROPERTY(bool messageIsError READ messageIsError NOTIFY changed)

public:
    explicit Account(QObject *parent = nullptr);
    ~Account() override;

    bool ready() const { return !m_path.isEmpty(); }
    QString userName() const { return m_userName; }
    QString realName() const { return m_realName; }
    QUrl avatar() const;
    bool autologin() const { return m_autologinUser == m_userName && !m_userName.isEmpty(); }
    QString autologinOther() const { return autologin() ? QString() : m_autologinUser; }
    bool autologinAvailable() const;
    bool busy() const { return m_busy; }
    QString message() const { return m_message; }
    bool messageIsError() const { return m_messageIsError; }

    Q_INVOKABLE void setRealName(const QString &name);
    Q_INVOKABLE void setAvatar(const QUrl &file);
    Q_INVOKABLE void removeAvatar();
    Q_INVOKABLE void changePassword(const QString &password);
    Q_INVOKABLE void setAutologin(bool enabled);
    Q_INVOKABLE void clearMessage();

Q_SIGNALS:
    void changed();
    // Пароль сменён — форма очищается.
    void passwordChanged();

private Q_SLOTS:
    void reload();

private:
    void readAutologin();
    void call(const QString &method, const QVariantList &args, const QString &done, const std::function<void(bool)> &after = {});
    void finish(const QString &message, bool error);

    QString m_path;
    QString m_userName;
    QString m_realName;
    QString m_iconFile;
    int m_revision = 0;
    QString m_autologinUser;
    bool m_busy = false;
    QString m_message;
    bool m_messageIsError = false;
    QFileSystemWatcher m_watcher;
    QTemporaryFile *m_avatarFile = nullptr;
};
