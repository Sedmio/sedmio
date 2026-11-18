#include "images.h"

#include <KFileItem>
#include <KIO/PreviewJob>

#include <QCoreApplication>
#include <QIcon>
#include <QPointer>

IconProvider::IconProvider()
    : QQuickImageProvider(QQuickImageProvider::Pixmap)
{
}

QPixmap IconProvider::requestPixmap(const QString &id, QSize *size, const QSize &requestedSize)
{
    const int side = qMax(requestedSize.width(), requestedSize.height()) > 0
        ? qMax(requestedSize.width(), requestedSize.height())
        : 64;

    QIcon icon = id.startsWith(QLatin1Char('/')) ? QIcon(id) : QIcon::fromTheme(id);
    if (icon.isNull())
        icon = QIcon::fromTheme(QStringLiteral("unknown"));

    const QPixmap pixmap = icon.pixmap(side, side);
    if (size)
        *size = pixmap.size();
    return pixmap;
}

namespace
{
class ThumbnailResponse : public QQuickImageResponse
{
public:
    ThumbnailResponse(const QUrl &url, const QString &mime, const QSize &size)
    {
        // Задания KIO живут в главном потоке, а сюда нас зовут из потока загрузки картинок.
        QPointer<ThumbnailResponse> self(this);
        QMetaObject::invokeMethod(
            QCoreApplication::instance(),
            [self, url, mime, size] {
                if (!self)
                    return;
                const QSize side = size.isValid() && !size.isEmpty() ? size : QSize(256, 256);
                KIO::PreviewJob *job = KIO::filePreview(KFileItemList{KFileItem(url, mime)}, side);
                job->setScaleType(KIO::PreviewJob::ScaledAndCached);
                self->m_job = job;
                QObject::connect(job, &KIO::PreviewJob::gotPreview, job, [self](const KFileItem &, const QPixmap &preview) {
                    if (!self)
                        return;
                    self->m_image = preview.toImage();
                    Q_EMIT self->finished();
                });
                QObject::connect(job, &KIO::PreviewJob::failed, job, [self](const KFileItem &) {
                    if (!self)
                        return;
                    self->m_failed = true;
                    Q_EMIT self->finished();
                });
            },
            Qt::QueuedConnection);
    }

    QQuickTextureFactory *textureFactory() const override
    {
        return QQuickTextureFactory::textureFactoryForImage(m_image);
    }

    QString errorString() const override
    {
        return m_failed ? QStringLiteral("no preview") : QString();
    }

    void cancel() override
    {
        QPointer<KIO::PreviewJob> job = m_job;
        QMetaObject::invokeMethod(
            QCoreApplication::instance(),
            [job] {
                if (job)
                    job->kill();
            },
            Qt::QueuedConnection);
    }

private:
    QPointer<KIO::PreviewJob> m_job;
    QImage m_image;
    bool m_failed = false;
};
} // namespace

QQuickImageResponse *ThumbnailProvider::requestImageResponse(const QString &id, const QSize &requestedSize)
{
    const int slash = id.indexOf(QLatin1Char('/'));
    const QString mime = QUrl::fromPercentEncoding(id.left(slash).toUtf8());
    const QUrl url(QUrl::fromPercentEncoding(id.mid(slash + 1).toUtf8()));
    return new ThumbnailResponse(url, mime, requestedSize);
}
