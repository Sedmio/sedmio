#include "textmatch.h"

#include <QHash>

namespace TextMatch
{

QString normalize(const QString &text)
{
    QString out;
    out.reserve(text.size());
    bool space = true;
    for (QChar c : text) {
        if (c.isLetterOrNumber()) {
            c = c.toLower();
            if (c == u'ё')
                c = u'е';
            out += c;
            space = false;
        } else if (!space) {
            out += u' ';
            space = true;
        }
    }
    if (out.endsWith(u' '))
        out.chop(1);
    return out;
}

QStringList words(const QString &normalized)
{
    return normalized.split(u' ', Qt::SkipEmptyParts);
}

QString swapLayout(const QString &normalized)
{
    static const QString latin = QStringLiteral("qwertyuiop[]asdfghjkl;'zxcvbnm,.`");
    static const QString cyrillic = QStringLiteral("йцукенгшщзхъфывапролджэячсмитьбюе");
    QString out;
    out.reserve(normalized.size());
    bool changed = false;
    for (QChar c : normalized) {
        qsizetype i = latin.indexOf(c);
        if (i >= 0) {
            out += cyrillic.at(i);
            changed = true;
            continue;
        }
        i = cyrillic.indexOf(c);
        if (i >= 0) {
            out += latin.at(i);
            changed = true;
            continue;
        }
        out += c;
    }
    // Знаки ([];',.`) нормализация уже убрала — их буквы (х, ъ, ж, э, б, ю,
    // ё) на латинице не набрать; оставшееся сравниваем нормализованным.
    return changed ? normalize(out) : QString();
}

QString transliterate(const QString &normalized)
{
    static const QHash<QChar, QString> map = {
        {u'а', QStringLiteral("a")},  {u'б', QStringLiteral("b")},  {u'в', QStringLiteral("v")},
        {u'г', QStringLiteral("g")},  {u'д', QStringLiteral("d")},  {u'е', QStringLiteral("e")},
        {u'ж', QStringLiteral("zh")}, {u'з', QStringLiteral("z")},  {u'и', QStringLiteral("i")},
        {u'й', QStringLiteral("y")},  {u'к', QStringLiteral("k")},  {u'л', QStringLiteral("l")},
        {u'м', QStringLiteral("m")},  {u'н', QStringLiteral("n")},  {u'о', QStringLiteral("o")},
        {u'п', QStringLiteral("p")},  {u'р', QStringLiteral("r")},  {u'с', QStringLiteral("s")},
        {u'т', QStringLiteral("t")},  {u'у', QStringLiteral("u")},  {u'ф', QStringLiteral("f")},
        {u'х', QStringLiteral("h")},  {u'ц', QStringLiteral("c")},  {u'ч', QStringLiteral("ch")},
        {u'ш', QStringLiteral("sh")}, {u'щ', QStringLiteral("sch")}, {u'ъ', QString()},
        {u'ы', QStringLiteral("y")},  {u'ь', QString()},            {u'э', QStringLiteral("e")},
        {u'ю', QStringLiteral("yu")}, {u'я', QStringLiteral("ya")},
    };
    QString out;
    bool changed = false;
    for (QChar c : normalized) {
        const auto it = map.constFind(c);
        if (it == map.constEnd()) {
            out += c;
            continue;
        }
        out += *it;
        changed = true;
    }
    return changed ? out : QString();
}

} // namespace TextMatch
