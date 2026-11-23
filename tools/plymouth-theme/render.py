"""Картинки темы Plymouth (заставка при загрузке) Sedmio.

    python3 tools/plymouth-theme/render.py

Нужны Pillow и rsvg-convert (librsvg). Кладёт PNG в
packages/sedmio-branding/plymouth/sedmio/ рядом с sedmio.plymouth.

Тема тёмная: надписи модуля two-step (запрос пароля диска, сообщения)
только белые, цвет не настраивается. Фон — градиент из sedmio.plymouth,
посередине знак Sedmio, ниже — кольцо-индикатор (throbber-*.png; те же
кадры — animation-*.png, без них two-step тему не грузит). Для пароля —
поле (entry.png), точки (bullet.png) и замок (lock.png, символ Lucide).
"""

import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "packages/sedmio-branding/plymouth/sedmio"
LOGO = ROOT / "packages/sedmio-calamares/files/etc/calamares/branding/sedmio/logo.svg"
LOCK = ROOT / "packages/sedmio-theme/symbols/lucide/lock.svg"

# Цвета — тёмные оттенки темы Sedmio (theme.json: ink #1B251F, leaf).
LIGHT = (232, 237, 227)      # wallpaperTop
LEAF = (168, 197, 159)       # светлый лист знака
FIELD = (38, 51, 43)
FIELD_LINE = (64, 82, 70)

SS = 4  # рисуем крупнее и уменьшаем — сглаживание


def svg_png(svg: bytes, size: int) -> Image.Image:
    png = subprocess.run(["rsvg-convert", "-w", str(size), "-h", str(size)],
                         input=svg, capture_output=True, check=True).stdout
    from io import BytesIO
    return Image.open(BytesIO(png)).convert("RGBA")


def spinner_frames(count=36, size=32, width=3):
    frames = []
    for i in range(count):
        big = Image.new("RGBA", (size * SS, size * SS), (0, 0, 0, 0))
        d = ImageDraw.Draw(big)
        box = [width * SS / 2, width * SS / 2, size * SS - width * SS / 2, size * SS - width * SS / 2]
        d.ellipse(box, outline=LIGHT + (36,), width=width * SS)
        start = i * 360 / count - 90
        d.arc(box, start, start + 100, fill=LEAF + (255,), width=width * SS)
        frames.append(big.resize((size, size), Image.LANCZOS))
    return frames


def rounded(size, radius, fill, outline=None):
    w, h = size
    big = Image.new("RGBA", (w * SS, h * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(big)
    d.rounded_rectangle([0, 0, w * SS - 1, h * SS - 1], radius * SS, fill=fill,
                        outline=outline, width=SS if outline else 0)
    return big.resize((w, h), Image.LANCZOS)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for old in OUT.glob("*.png"):
        old.unlink()

    svg_png(LOGO.read_bytes(), 112).save(OUT / "watermark.png")

    for n, frame in enumerate(spinner_frames(), 1):
        frame.save(OUT / f"throbber-{n:04d}.png")
        frame.save(OUT / f"animation-{n:04d}.png")

    rounded((300, 42), 12, FIELD + (255,), FIELD_LINE + (255,)).save(OUT / "entry.png")
    dot = Image.new("RGBA", (10 * SS, 10 * SS), (0, 0, 0, 0))
    ImageDraw.Draw(dot).ellipse([0, 0, 10 * SS - 1, 10 * SS - 1], fill=LIGHT + (255,))
    dot.resize((10, 10), Image.LANCZOS).save(OUT / "bullet.png")

    lock = LOCK.read_bytes().replace(b"currentColor", b"#E8EDE3").replace(b'stroke-width="2"', b'stroke-width="1.75"')
    svg_png(lock, 24).save(OUT / "lock.png")
    print(f"{len(list(OUT.glob('*.png')))} картинок в {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    sys.exit(main())
