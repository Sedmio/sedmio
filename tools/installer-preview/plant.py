"""Стенд для растения: седум крупно на нескольких стадиях роста.

    python plant.py                               # окно: стадии 1, 4, 6 и цветение
    python plant.py --shot out/plant.png          # то же в файл
    python plant.py --stages 0,1,2,3 --size 380   # свои стадии и размер
    python plant.py --all --shot out/stages.png   # все стадии 0..7 и цветение
    python plant.py --all --bloom ...             # все стадии, каждая цветёт
    python plant.py --zoom 6 --shot out/zoom.png  # одно растение крупно (--bloom — с цветами)
    python plant.py --logo --shot out/logo.png    # знак в размерах шапки и увеличенно
    python plant.py --leaves --shot out/leaves.png  # листья по одному: возраст, румянец, свет
    python plant.py --dark ...                    # на тёмном фоне: видны ореолы и огрехи краёв
    python plant.py --check-bloom                 # не выходят ли цветы за листву (все стадии, разные размеры)

Ошибки QML печатаются в stderr.
"""

import argparse
import os
import sys
import time
from pathlib import Path

os.environ.setdefault("QT_FORCE_STDERR_LOGGING", "1")

from PySide6.QtCore import QEventLoop, Qt, QTimer, QUrl  # noqa: E402
from PySide6.QtGui import QGuiApplication, QImage, QPainter  # noqa: E402
from PySide6.QtQml import QQmlApplicationEngine  # noqa: E402
from PySide6.QtQuick import QQuickWindow  # noqa: E402, F401

HERE = Path(__file__).resolve().parent
BRANDING = HERE.parents[1] / "packages/sedmio-calamares/files/etc/calamares/branding/sedmio"

HEAD = """
import QtQuick
import QtQuick.Window
import "components"
"""


def grid_qml(stages, bloom_all, bloom_last, size, columns, background, extra=""):
    """Сетка растений. extra — дополнительные свойства Sedum (например, potted: false)."""
    flag = "true" if bloom_all else "false"
    cells = [f"{{ stage: {s}, bloom: {flag}, label: 'стадия {s}' }}" for s in stages]
    if bloom_last:
        cells.append("{ stage: 7, bloom: true, label: 'цветение' }")
    rows = -(-len(cells) // columns)
    labels = 0 if extra else 24
    return HEAD + f"""
Window {{
    width: {columns * (size + 10) + 30}; height: {rows * (size + 10 + labels) + 20}; visible: true
    color: {background}
    title: "Sedmio — стенд растения"

    Grid {{
        x: 15; y: 10
        columns: {columns}
        spacing: 10
        Repeater {{
            model: [{", ".join(cells)}]
            delegate: Column {{
                spacing: 4
                Sedum {{ size: {size}; stage: modelData.stage; blooming: modelData.bloom; {extra} }}
                Text {{ text: modelData.label; font.pixelSize: 14; color: Theme.inkMuted; visible: {labels} > 0
                       anchors.horizontalCenter: parent.horizontalCenter }}
            }}
        }}
    }}
}}
"""


def zoom_qml(stage, bloom, size, background):
    return HEAD + f"""
Window {{
    width: {size + 40}; height: {size + 40}; visible: true
    color: {background}
    title: "Sedmio — растение крупно"

    Sedum {{
        anchors.centerIn: parent
        size: {size}; stage: {stage}; blooming: {"true" if bloom else "false"}
    }}
}}
"""


LOGO_QML = HEAD + """
Window {
    width: 420; height: 90; visible: true
    color: Theme.paper
    title: "Sedmio — знак"

    Row {
        anchors.centerIn: parent
        spacing: 28
        Repeater {
            model: [16, 20, 26, 28, 40, 64]
            delegate: Logo { size: modelData; anchors.verticalCenter: parent.verticalCenter }
        }
    }
}
"""


def leaves_qml(length, background):
    """Листья по одному: возраст, румянец и повороты к свету."""
    cell = int(length * 1.25)
    return HEAD + f"""
Window {{
    width: {cell} * 6 + 40; height: {cell} * 2 + 40; visible: true
    color: {background}
    title: "Sedmio — листья"

    Grid {{
        anchors.centerIn: parent
        columns: 6
        Repeater {{
            model: [
                {{ youth: 1.0, blush: 0, turn: 0, cover: 0 }},
                {{ youth: 0.6, blush: 0, turn: 0, cover: 0.2 }},
                {{ youth: 0.25, blush: 0, turn: 0, cover: 0.4 }},
                {{ youth: 0, blush: 0.15, turn: 0, cover: 0.55 }},
                {{ youth: 0, blush: 0.55, turn: 0, cover: 0.62 }},
                {{ youth: 0, blush: 1, turn: 0, cover: 0.68 }},
                {{ youth: 0, blush: 0.6, turn: 60, cover: 0.6 }},
                {{ youth: 0, blush: 0.6, turn: 120, cover: 0.6 }},
                {{ youth: 0, blush: 0.6, turn: 180, cover: 0.6 }},
                {{ youth: 0, blush: 0.6, turn: 240, cover: 0.6 }},
                {{ youth: 0, blush: 0.6, turn: 300, cover: 0.6 }},
                {{ youth: 0.5, blush: 0, turn: 200, cover: 0.3 }}
            ]
            delegate: Item {{
                width: {cell}; height: {cell}
                Leaf {{
                    id: leaf
                    length: {length} * (1 - 0.45 * modelData.youth)
                    breadth: length * (0.52 + 0.4 * modelData.youth)
                    youth: modelData.youth; blush: modelData.blush
                    azimuth: modelData.turn; cover: modelData.cover
                    seed: index + 1
                    x: parent.width / 2 - baseX
                    y: parent.height / 2 - baseY
                    transform: [
                        Translate {{ y: leaf.length / 2 }},
                        Rotation {{ origin.x: leaf.baseX; origin.y: leaf.baseY - 0; angle: modelData.turn }}
                    ]
                }}
            }}
        }}
    }}
}}
"""


def wait(ms):
    loop = QEventLoop()
    QTimer.singleShot(ms, loop.quit)
    loop.exec()


def render(qml, ms):
    """Загрузить QML, подождать и вернуть снимок окна."""
    engine = QQmlApplicationEngine()
    engine.loadData(qml.encode("utf-8"), QUrl.fromLocalFile(str(BRANDING / "_stand.qml")))
    if not engine.rootObjects():
        raise SystemExit(1)
    window = engine.rootObjects()[0]
    wait(ms)
    image = window.grabWindow()
    window.close()
    engine.deleteLater()
    wait(50)
    return image


def check_bloom(sizes, ms):
    """Цветы и стебли не должны выходить за листву: ни на одной стадии, ни при каком размере.

    Растение без горшка рисуется на пурпурном фоне дважды — без цветов и с цветами.
    Листва — там, где в первом снимке есть зелёное; цветы и стебли — там, где
    зелёный канал вырос во втором. Считаем пиксели цветов вне листвы.
    """
    stages = list(range(8))
    extra = "potted: false; still: true"
    worst = 0
    print("Пиксели цветов и стеблей за пределами листвы (0 — всё на листьях):")
    print("размер  " + "".join(f"  ст.{s}" for s in stages))
    for size in sizes:
        columns = max(1, min(len(stages), 1700 // (size + 10)))     # окно не шире экрана
        row = []
        for first in range(0, len(stages), columns):
            batch = stages[first:first + columns]
            shots = []
            for bloom in (False, True):
                qml = grid_qml(batch, bloom, False, size, columns, '"#FF00FF"', extra)
                shots.append(render(qml, ms if bloom else 1200).convertToFormat(QImage.Format_RGB888))
            plain, flowers = shots
            width, height, stride = plain.width(), plain.height(), plain.bytesPerLine()
            a, b = bytes(plain.constBits()), bytes(flowers.constBits())
            for index in range(len(batch)):
                left, top = 15 + index * (size + 10), 10
                if left + size > width or top + size > height:
                    raise SystemExit(f"снимок {width}x{height} меньше сетки: стадия {batch[index]} не попала в кадр")
                outside = spray = 0
                for y in range(top, top + size):
                    base = y * stride
                    for x in range(left, left + size):
                        g0, g1 = a[base + x * 3 + 1], b[base + x * 3 + 1]
                        if g1 > 70 and g1 - g0 > 40:        # здесь появился цветок или стебель
                            spray += 1
                            if g0 <= 45:                    # а листа под ним нет
                                outside += 1
                row.append((outside, spray))
                worst = max(worst, outside)
            flowers.save(str(HERE / "out" / f"check-bloom-{size}-{batch[0]}.png"))
        print(f"{size:6}  " + "".join(f"{o:6}" for o, _ in row) + "    (всего пикселей цветов: "
              + ", ".join(str(s) for _, s in row) + ")")
    print("итог:", "цветы нигде не выходят за листву" if worst <= 3 else f"ЕСТЬ ВЫХОД ЗА ЛИСТВУ (до {worst} px)")
    return 0 if worst <= 3 else 2


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--shot", metavar="PNG", help="сохранить картинку и выйти")
    parser.add_argument("--stages", default="1,4,6", help="стадии через запятую")
    parser.add_argument("--all", action="store_true", help="все стадии 0..7")
    parser.add_argument("--no-bloom", action="store_true", help="без цветущего растения в конце сетки")
    parser.add_argument("--bloom", action="store_true", help="цветут все растения сетки (или растение --zoom)")
    parser.add_argument("--bare", action="store_true", help="без горшка")
    parser.add_argument("--size", type=int, default=0, help="размер растения, px")
    parser.add_argument("--columns", type=int, default=0)
    parser.add_argument("--zoom", type=float, metavar="STAGE", help="одно растение крупно")
    parser.add_argument("--logo", action="store_true", help="знак в разных размерах")
    parser.add_argument("--leaves", action="store_true", help="листья по одному: возраст, румянец, свет")
    parser.add_argument("--check-bloom", action="store_true", help="проверить, что цветы не выходят за листву")
    parser.add_argument("--dark", action="store_true", help="тёмный фон")
    parser.add_argument("--wait", type=int, default=3600, help="пауза перед снимком, мс")
    parser.add_argument("--time", action="store_true", help="напечатать время загрузки и первых кадров")
    parser.add_argument("--magnify", type=int, default=0, help="увеличить снимок в N раз по пикселям")
    args = parser.parse_args()

    app = QGuiApplication(sys.argv)

    if args.check_bloom:
        (HERE / "out").mkdir(exist_ok=True)
        sizes = [args.size] if args.size else [220, 300, 440, 600]
        return check_bloom(sizes, max(args.wait, 4800))

    background = '"#26302B"' if args.dark else "Theme.paper"
    magnify = args.magnify
    if args.logo:
        qml = LOGO_QML
        magnify = magnify or 6
    elif args.leaves:
        qml = leaves_qml(args.size or 240, background)
    elif args.zoom is not None:
        qml = zoom_qml(args.zoom, args.bloom, args.size or 860, background)
    else:
        stages = list(range(8)) if args.all else [float(s) for s in args.stages.split(",")]
        stages = [int(s) if float(s).is_integer() else s for s in stages]
        last = not args.no_bloom and not args.bloom
        count = len(stages) + (1 if last else 0)
        columns = args.columns or (3 if count <= 6 else 4 if count <= 8 else 5)
        qml = grid_qml(stages, args.bloom, last, args.size or 420, columns, background,
                       "potted: false" if args.bare else "")

    engine = QQmlApplicationEngine()
    started = time.perf_counter()
    engine.loadData(qml.encode("utf-8"), QUrl.fromLocalFile(str(BRANDING / "_stand.qml")))
    if not engine.rootObjects():
        return 1
    window = engine.rootObjects()[0]
    if args.time:
        # Сколько занял запуск и первые кадры: запекание листьев идёт в фоне и кадры не держит
        print(f"загрузка QML: {(time.perf_counter() - started) * 1000:.0f} мс", file=sys.stderr)
        frames = []

        def swapped():
            frames.append(time.perf_counter())
            if len(frames) <= 4:
                print(f"кадр {len(frames)}: {(frames[-1] - started) * 1000:.0f} мс от старта", file=sys.stderr)

        window.frameSwapped.connect(swapped, Qt.DirectConnection)
    if args.shot:
        wait(args.wait)
        Path(args.shot).parent.mkdir(parents=True, exist_ok=True)
        image = window.grabWindow()
        if magnify > 1:
            # Сверху настоящий размер, снизу — те же пиксели увеличенно
            big = image.scaled(image.width() * magnify, image.height() * magnify,
                               Qt.KeepAspectRatio, Qt.FastTransformation)
            sheet = QImage(big.width(), big.height() + image.height(), QImage.Format_ARGB32)
            sheet.fill(image.pixelColor(0, 0))
            painter = QPainter(sheet)
            painter.drawImage(0, 0, image)
            painter.drawImage(0, image.height(), big)
            painter.end()
            image = sheet
        image.save(args.shot)
        print("сохранено:", args.shot, f"{image.width()}x{image.height()}")
        return 0
    return app.exec()


if __name__ == "__main__":
    code = main()
    sys.stdout.flush()
    os._exit(code)
