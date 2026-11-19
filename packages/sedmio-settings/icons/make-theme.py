#!/usr/bin/python3 -I
"""Тема значков Sedmio: Breeze с более заметными знаками на папках.

У цветных папок Breeze тело папки — цвет акцента (ColorScheme-Accent), а
знак на ней (загрузка, музыка, картинка…) — цвет текста. У Breeze акцент
светло-голубой, у Sedmio — тёмно-зелёный, и тёмный знак на нём почти не
виден. Здесь знак становится белым с той же прозрачностью.

Раздел places Breeze повторяем целиком (неизменённое — ссылками на файлы
Breeze) с теми же описаниями каталогов: значок ищется сначала в нашей
теме, и если бы у нас были только крупные папки, их брали бы и для 16 px
вместо маленьких значков Breeze. Всё прочее тема берёт у Breeze (Inherits).

make-theme.py <каталог breeze> <куда положить тему>
"""

import os
import re
import sys

ELEMENT = re.compile(r"<(?:path|rect|circle|ellipse|polygon|g)\b[^>]*>", re.S)


def lighten(svg):
    def fix(match):
        element = match.group(0)
        if 'class="ColorScheme-Text"' in element and "fill:currentColor" in element:
            return element.replace("fill:currentColor", "fill:#ffffff")
        return element

    return ELEMENT.sub(fix, svg)


SKIP = ("Name", "Comment", "Inherits", "Directories", "ScaledDirectories", "Hidden")


def places_sections(breeze):
    """Секции [places/…] из index.theme Breeze (имя → строки) и строки
    [Icon Theme] кроме имени и каталогов: FollowsColorScheme (без неё KDE не
    красит папки в цвет акцента), размеры по умолчанию, KDE-Extensions."""
    sections = {}
    header = []
    current = None
    with open(os.path.join(breeze, "index.theme"), encoding="utf-8") as f:
        for line in f:
            stripped = line.strip()
            if stripped.startswith("["):
                name = stripped[1:-1]
                current = name if name.startswith("places/") or name == "Icon Theme" else None
                if current and current != "Icon Theme":
                    sections[current] = []
            elif current and stripped and not stripped.startswith("#"):
                if current != "Icon Theme":
                    sections[current].append(stripped)
                elif "=" in stripped and not stripped.split("=")[0].split("[")[0] in SKIP:
                    header.append(stripped)
    return sections, header


def main(breeze, out):
    breeze = os.path.abspath(breeze)
    sections, header = places_sections(breeze)
    if "FollowsColorScheme=true" not in header:
        sys.exit("make-theme.py: у Breeze нет FollowsColorScheme=true — проверьте")
    changed = 0
    present = []
    for directory in sections:
        source = os.path.join(breeze, directory)
        if not os.path.isdir(source):
            continue
        present.append(directory)
        target = os.path.join(out, directory)
        os.makedirs(target, exist_ok=True)
        for name in sorted(os.listdir(source)):
            path = os.path.join(source, name)
            destination = os.path.join(target, name)
            if os.path.islink(path):
                link = os.readlink(path)
                if os.path.dirname(link) in ("", "."):
                    os.symlink(os.path.basename(link), destination)  # на наш вариант
                else:
                    os.symlink(os.path.realpath(path), destination)
                continue
            if name.endswith(".svg"):
                with open(path, encoding="utf-8") as f:
                    svg = f.read()
                if "ColorScheme-Accent" in svg:
                    fixed = lighten(svg)
                    if fixed != svg:
                        with open(destination, "w", encoding="utf-8") as f:
                            f.write(fixed)
                        changed += 1
                        continue
            os.symlink(path, destination)

    plain = [d for d in present if "@" not in d]
    scaled = [d for d in present if "@" in d]
    with open(os.path.join(out, "index.theme"), "w", encoding="utf-8") as f:
        f.write("[Icon Theme]\n"
                "Name=Sedmio\n"
                "Comment=Breeze with clearer folder emblems\n"
                "Comment[ru]=Breeze с более заметными знаками на папках\n"
                "Inherits=breeze,hicolor\n"
                "Hidden=false\n"
                + "".join(line + "\n" for line in header)
                + f"Directories={','.join(plain)}\n")
        if scaled:
            f.write(f"ScaledDirectories={','.join(scaled)}\n")
        for directory in present:
            f.write(f"\n[{directory}]\n" + "\n".join(sections[directory]) + "\n")

    if changed < 50:
        sys.exit(f"make-theme.py: перекрашено только {changed} значков — Breeze устроен иначе, проверьте")
    print(f"make-theme.py: перекрашено {changed} значков")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
