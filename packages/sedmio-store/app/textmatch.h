#pragma once

#include <QString>
#include <QStringList>

// Поиск по каталогу — свой, а не AppStream: у того порядок выдачи плохой
// («vlc» — на первом месте не VLC). Строки сравниваем нормализованными:
// строчные буквы, ё → е, без знаков. Запрос пробуем и в другой раскладке
// («ашкуащч» → «firefox») и латиницей («телеграм» → «telegram»).
namespace TextMatch
{

// Строчные, ё → е, всё, кроме букв и цифр, — пробел, пробелы схлопнуты.
QString normalize(const QString &text);

// Слова нормализованной строки.
QStringList words(const QString &normalized);

// Набранное не в той раскладке: йцукен ↔ qwerty. Пусто, если менять нечего.
QString swapLayout(const QString &normalized);

// Кириллица латиницей, грубо, по звучанию («телеграм» → «telegram»). Пусто,
// если кириллицы нет.
QString transliterate(const QString &normalized);

} // namespace TextMatch
