#pragma once

#include <QQuickAsyncImageProvider>
#include <QQuickImageProvider>

// image://icon/<имя> — значок из темы (или файл по абсолютному пути).
class IconProvider : public QQuickImageProvider
{
public:
    IconProvider();
    QPixmap requestPixmap(const QString &id, QSize *size, const QSize &requestedSize) override;
};

// image://thumb/<mime>/<адрес> — миниатюра файла (обе части через
// encodeURIComponent). Делает KIO::PreviewJob, миниатюры кешируются в
// ~/.cache/thumbnails, как у Dolphin.
class ThumbnailProvider : public QQuickAsyncImageProvider
{
public:
    QQuickImageResponse *requestImageResponse(const QString &id, const QSize &requestedSize) override;
};
