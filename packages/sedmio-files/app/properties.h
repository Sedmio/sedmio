#pragma once

#include <KFileItem>
#include <KIO/DirectorySizeJob>

#include <QDateTime>
#include <QObject>
#include <QPointer>
#include <QTimer>
#include <QUrl>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

// Свойства файла, папки или нескольких выбранных сразу — для окна
// «Свойства». Сведения берёт KIO (работает и для сети, и для корзины),
// размер папок считает в фоне и показывает, сколько насчитал на ходу.
class Properties : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(QList<QUrl> urls READ urls WRITE setUrls NOTIFY urlsChanged)
    // Сведения пришли (для сети это не сразу).
    Q_PROPERTY(bool ready READ ready NOTIFY changed)
    Q_PROPERTY(QString error READ error NOTIFY changed)
    Q_PROPERTY(int count READ count NOTIFY urlsChanged)

    Q_PROPERTY(QString name READ name NOTIFY changed)
    Q_PROPERTY(QString iconName READ iconName NOTIFY changed)
    Q_PROPERTY(QString mimeType READ mimeType NOTIFY changed)
    // «Изображение PNG»; у нескольких разных — пусто.
    Q_PROPERTY(QString typeName READ typeName NOTIFY changed)
    // Папка, где лежит (у нескольких — общая, если есть).
    Q_PROPERTY(QUrl parentUrl READ parentUrl NOTIFY changed)
    Q_PROPERTY(bool isDir READ isDir NOTIFY changed)
    // Один файл, у которого есть миниатюра.
    Q_PROPERTY(bool canPreview READ canPreview NOTIFY changed)
    Q_PROPERTY(bool isLocal READ isLocal NOTIFY changed)
    Q_PROPERTY(QString linkTarget READ linkTarget NOTIFY changed)
    Q_PROPERTY(QDateTime modified READ modified NOTIFY changed)
    Q_PROPERTY(QDateTime accessed READ accessed NOTIFY changed)
    Q_PROPERTY(QDateTime created READ created NOTIFY changed)

    // Размер: у папок растёт, пока идёт подсчёт.
    Q_PROPERTY(qreal size READ size NOTIFY sizeChanged)
    Q_PROPERTY(bool counting READ counting NOTIFY sizeChanged)
    Q_PROPERTY(qint64 files READ files NOTIFY sizeChanged)
    Q_PROPERTY(qint64 folders READ folders NOTIFY sizeChanged)

    // Права (только у одного локального): биты 0777, чьё, можно ли менять.
    Q_PROPERTY(int mode READ mode NOTIFY changed)
    Q_PROPERTY(QString owner READ owner NOTIFY changed)
    Q_PROPERTY(QString group READ group NOTIFY changed)
    Q_PROPERTY(bool canChangeMode READ canChangeMode NOTIFY changed)

    // Диск, на котором лежит: всего и свободно (0 — неизвестно).
    Q_PROPERTY(qreal diskSize READ diskSize NOTIFY diskChanged)
    Q_PROPERTY(qreal diskFree READ diskFree NOTIFY diskChanged)

    // Чем открывается этот тип: {id, name, icon}; пусто — ничем.
    Q_PROPERTY(QVariantMap application READ application NOTIFY applicationChanged)

public:
    explicit Properties(QObject *parent = nullptr);
    ~Properties() override;

    QList<QUrl> urls() const { return m_urls; }
    void setUrls(const QList<QUrl> &urls);

    bool ready() const { return m_pending == 0 && !m_items.isEmpty(); }
    QString error() const { return m_error; }
    int count() const { return m_urls.size(); }

    QString name() const;
    QString iconName() const;
    QString mimeType() const;
    QString typeName() const;
    QUrl parentUrl() const;
    bool isDir() const;
    bool canPreview() const;
    bool isLocal() const;
    QString linkTarget() const;
    QDateTime modified() const;
    QDateTime accessed() const;
    QDateTime created() const;

    qreal size() const { return m_size; }
    bool counting() const { return m_sizeJob; }
    qint64 files() const { return m_files; }
    qint64 folders() const { return m_folders; }

    int mode() const;
    QString owner() const;
    QString group() const;
    bool canChangeMode() const;

    qreal diskSize() const { return m_diskSize; }
    qreal diskFree() const { return m_diskFree; }

    QVariantMap application() const;

    // Доступ: who — 0 владелец, 1 группа, 2 остальные; level — 0 нет,
    // 1 только чтение, 2 чтение и запись. У папок чтение идёт вместе
    // с правом заходить в неё.
    Q_INVOKABLE void setAccess(int who, int level);
    // Можно ли запускать файл как программу.
    Q_INVOKABLE void setExecutable(bool executable);
    // Открывать этот тип такой программой (id из FileOps.applications).
    Q_INVOKABLE void setApplication(const QString &serviceId);

Q_SIGNALS:
    void urlsChanged();
    void changed();
    void sizeChanged();
    void diskChanged();
    void applicationChanged();

private:
    void itemsReady();
    void startCounting();
    void applyMode(int mode);
    void refreshItem();

    QList<QUrl> m_urls;
    KFileItemList m_items;
    int m_pending = 0;
    QString m_error;

    QPointer<KIO::DirectorySizeJob> m_sizeJob;
    QTimer m_sizeTimer;
    qreal m_size = 0;
    qint64 m_files = 0;
    qint64 m_folders = 0;

    qreal m_diskSize = 0;
    qreal m_diskFree = 0;
};
