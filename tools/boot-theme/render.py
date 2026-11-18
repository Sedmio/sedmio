"""Картинки для темы меню загрузки (GRUB) образа Sedmio.

    tools/installer-preview/.venv/Scripts/python tools/boot-theme/render.py

Рисует из тех же QML-компонентов, что и установщик (растение, знак,
палитра), и кладёт PNG в iso/grub/themes/sedmio/ (меню UEFI) и заставку
iso/syslinux/splash.png (меню BIOS). Шрифты (*.pf2) делает
scripts/build-iso.sh через grub-mkfont: для этого нужен Linux.

GRUB растягивает фон под экран, а картинки (растение, шапку) ставит как
есть, по процентам от размера экрана. Поэтому фон — только бумага и
размытые пятна, которым растяжение не вредит, а растение отдельно.
"""

import os
import sys
from pathlib import Path

os.environ.setdefault("QT_FORCE_STDERR_LOGGING", "1")
# Без экрана: обычное окно система ужимает до свободной высоты экрана
# (фон выходил 1920×1061 вместо 1920×1080). Шрифт Onest грузится из файла.
os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from PySide6.QtCore import QEventLoop, QRectF, Qt, QTimer, QUrl  # noqa: E402
from PySide6.QtGui import QColor, QGuiApplication, QImage, QPainter, QPainterPath  # noqa: E402
from PySide6.QtQml import QQmlApplicationEngine  # noqa: E402
from PySide6.QtQuick import QQuickWindow  # noqa: E402, F401  (даёт окнам grabWindow)

ROOT = Path(__file__).resolve().parents[2]
BRANDING = ROOT / "packages/sedmio-calamares/files/etc/calamares/branding/sedmio"
OUT = ROOT / "iso/grub/themes/sedmio"

# Палитра — как в components/Theme.qml
GREEN = "#2F5D46"

HEAD = """
import QtQuick
import QtQuick.Window
import QtQuick.Shapes
import "components"
"""

# Фон 1920×1080: бумага и два мягких пятна там, где будет растение
BACKGROUND = HEAD + """
Window {
    width: 1920; height: 1080; visible: true
    color: Theme.paper

    component Blob: Shape {
        id: blob
        property color tint
        property real strength: 0.7
        readonly property real r: width / 2
        height: width
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeWidth: -1
            fillGradient: RadialGradient {
                centerX: blob.r; centerY: blob.r; centerRadius: blob.r
                focalX: blob.r; focalY: blob.r
                GradientStop { position: 0.0; color: Qt.rgba(blob.tint.r, blob.tint.g, blob.tint.b, blob.strength) }
                GradientStop { position: 0.45; color: Qt.rgba(blob.tint.r, blob.tint.g, blob.tint.b, blob.strength * 0.55) }
                GradientStop { position: 0.75; color: Qt.rgba(blob.tint.r, blob.tint.g, blob.tint.b, blob.strength * 0.18) }
                GradientStop { position: 1.0; color: Qt.rgba(blob.tint.r, blob.tint.g, blob.tint.b, 0) }
            }
            PathAngleArc { centerX: blob.r; centerY: blob.r; radiusX: blob.r; radiusY: blob.r; sweepAngle: 360 }
        }
    }

    Blob { tint: Theme.leafPale; strength: 0.8; width: 1250; x: 1920 * 0.70 - 625; y: 1080 * 0.48 - 625 }
    Blob { tint: Theme.terracottaSoft; strength: 0.75; width: 820; x: 1920 * 0.80 - 410; y: 1080 * 0.66 - 410 }
    Blob { tint: Theme.leafPale; strength: 0.45; width: 900; x: -380; y: 1080 - 420 }
}
"""

# Седум в горшке, на прозрачном фоне
PLANT = HEAD + """
Window {
    width: 620; height: 620; visible: true
    color: "transparent"
    Sedum { anchors.centerIn: parent; size: 540; stage: 6; still: true }
}
"""

# Шапка: знак и слово «sedmio», как в шапке установщика, только крупнее
HEADER = HEAD + """
Window {
    width: 300; height: 72; visible: true
    color: "transparent"
    Row {
        anchors.verticalCenter: parent.verticalCenter
        x: 4
        spacing: 14
        Logo { size: 60; anchors.verticalCenter: parent.verticalCenter }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "sedmio"
            font.family: Theme.fontFamily
            font.pixelSize: 38
            font.weight: Font.DemiBold
            color: Theme.ink
        }
    }
}
"""


# Заставка меню syslinux (загрузка в режиме BIOS): ровно 640×480, текст
# меню там светлый, поэтому фон тёмный. Кириллицы syslinux не знает.
SPLASH = HEAD + """
Window {
    width: 640; height: 480; visible: true
    color: Theme.ink
    Sedum { x: 640 - 230; y: 480 - 235; size: 240; stage: 6; still: true }
}
"""


def wait(ms):
    loop = QEventLoop()
    QTimer.singleShot(ms, loop.quit)
    loop.exec()


def render(qml, ms, name, out=None):
    engine = QQmlApplicationEngine()
    engine.loadData(qml.encode("utf-8"), QUrl.fromLocalFile(str(BRANDING / "_boot.qml")))
    if not engine.rootObjects():
        raise SystemExit(f"{name}: ошибка QML")
    window = engine.rootObjects()[0]
    wait(ms)
    image = window.grabWindow()
    window.close()
    engine.deleteLater()
    wait(50)
    image.save(str((out or OUT) / name))
    print(f"{name}: {image.width()}x{image.height()}")


def box(name, color, height, radius, border=None, pill=False):
    """Скруглённый прямоугольник, разрезанный на 9 частей, как их ждёт GRUB
    (name_nw.png … name_se.png): углы — как есть, края и середина
    растягиваются.

    pill — «пилюля» ровно в высоту пункта меню: только левый край, середина
    и правый край (name_w/c/e.png). GRUB рисует верхние и нижние части
    рамки СНАРУЖИ пункта, и с ними подложка налезала на соседние пункты."""
    c = min(radius, (height - 2) // 2)          # размер угловой части
    if pill:
        c = height // 2
    size = 2 * c + 2
    full = QImage(size, height, QImage.Format_ARGB32_Premultiplied)
    full.fill(Qt.transparent)
    p = QPainter(full)
    p.setRenderHint(QPainter.Antialiasing)
    path = QPainterPath()
    inset = 0.5 if border else 0
    path.addRoundedRect(QRectF(inset, inset, size - 2 * inset, height - 2 * inset), radius, radius)
    p.fillPath(path, QColor(color))
    if border:
        p.setPen(QColor(border))
        p.drawPath(path)
    p.end()
    cols = {"w": (0, c), "": (c, 2), "e": (c + 2, c)}
    rows = {"n": (0, c), "": (c, height - 2 * c), "s": (height - c, c)}
    if pill:
        rows = {"": (0, height)}
    for old in OUT.glob(f"{name}_*.png"):
        old.unlink()
    for rk, (y, h) in rows.items():
        for ck, (x, w) in cols.items():
            part = rk + ck or "c"
            full.copy(x, y, w, h).save(str(OUT / f"{name}_{part}.png"))
    print(f"{name}_*.png: высота {height}, скругление {radius}")


def main():
    app = QGuiApplication(sys.argv)  # noqa: F841
    OUT.mkdir(parents=True, exist_ok=True)
    (ROOT / "iso/syslinux").mkdir(exist_ok=True)
    render(BACKGROUND, 600, "background.png")
    render(HEADER, 800, "header.png")
    render(PLANT, 4000, "plant.png")
    box("select", GREEN, height=56, radius=28, pill=True)                          # выбранный пункт
    render(SPLASH, 4000, "splash.png", ROOT / "iso/syslinux")
    box("terminal_box", "#F8FAF5", height=64, radius=16, border="#D5DCCF")  # правка параметров (E)


if __name__ == "__main__":
    main()
