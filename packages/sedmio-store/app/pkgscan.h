#pragma once

#include <QList>
#include <QString>
#include <QStringList>
#include <QVariantMap>

// Автопроверка пакета AUR перед сборкой: подсказка, на какие строки
// посмотреть. Только читает текст — ничего из пакета не выполняется
// (makepkg --printsrcinfo уже выполнил бы PKGBUILD). «Ничего не нашлось»
// не значит «безопасно»: просмотр нужен всегда.
//
// Уровни: danger — так делают вредоносные пакеты; check — бывает и в
// честных, но стоит понять зачем; note — к сведению.
namespace PkgScan
{
struct Finding {
    QString level;   // danger | check | note
    QString file;    // "" — про пакет в целом (сведения AUR)
    int line = 0;    // с 1; 0 — без строки
    QString message;
};

struct File {
    QString name;    // путь в архиве: PKGBUILD, foo.install, …
    QString text;
};

// Сведения AUR о пакете (Aur::fromJson) и с чем сравнивать.
struct Record {
    QString name;
    QString maintainer;
    QString previousMaintainer; // кто сопровождал при прошлой установке; "" — не знаем
    qint64 firstSubmitted = 0;  // секунды
    bool outOfDate = false;
    int votes = 0;
};

// files — текстовые файлы пакета; srcinfo — .SRCINFO (источники и суммы
// без выполнения PKGBUILD); repoNames — имена пакетов в репозиториях (для
// «похожего имени»).
QList<Finding> scan(const QList<File> &files, const QString &srcinfo, const Record &record, const QStringList &repoNames);

QVariantMap toMap(const Finding &finding);

// Источники VCS из .SRCINFO, которые следят за веткой (без #commit/#tag):
// [{url, ref}] — ref: "HEAD" или refs/heads/<ветка>.
QList<QPair<QString, QString>> vcsSources(const QString &srcinfo);
} // namespace PkgScan
