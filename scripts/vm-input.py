#!/usr/bin/env python3
"""Мышь, клавиатура и снимок экрана виртуалки из run-vm.sh (через QMP).

  scripts/vm-input.py shot файл.png          снимок экрана (1600×900)
  scripts/vm-input.py move X Y               подвести мышь
  scripts/vm-input.py click X Y [right|middle]
  scripts/vm-input.py drag X1 Y1 X2 Y2       перетащить левой кнопкой
  scripts/vm-input.py wheel X Y up|down [N]  колесо
  scripts/vm-input.py key meta_l print       сочетание клавиш (qcode QEMU)
  scripts/vm-input.py type hello             латиница, цифры, пробел, .,-/

Координаты — в точках экрана виртуалки. Названия клавиш — qcode QEMU:
ctrl, shift, alt, meta_l, ret, esc, tab, spc, backspace, print, f1…,
up/down/left/right, a…z, 0…9, dot, comma, minus, slash.

Монитор HMP (mouse_move, sendkey) до гостя не доходит — только QMP
input-send-event. Qt меняет наведение (hover) только при движении мыши,
поэтому move и click после прыжка сдвигают курсор ещё на точку.
"""
import json
import socket
import sys
import time
from pathlib import Path

SOCK = Path(__file__).resolve().parent.parent / "out/vm/qmp.sock"
W, H = 1600, 900  # разрешение из run-vm.sh (-device VGA,xres,yres)

# Символ → qcode для type.
CHARS = {" ": "spc", ".": "dot", ",": "comma", "-": "minus", "/": "slash"}


class Qmp:
    def __init__(self):
        self.sock = socket.socket(socket.AF_UNIX)
        self.sock.connect(str(SOCK))
        self.file = self.sock.makefile("rw")
        self.file.readline()  # приветствие
        self.cmd("qmp_capabilities")

    def cmd(self, name, **args):
        self.file.write(json.dumps({"execute": name, "arguments": args}) + "\n")
        self.file.flush()
        while True:  # события пропускаем, ждём ответ
            reply = json.loads(self.file.readline())
            if "error" in reply:
                raise SystemExit(f"QMP: {reply['error'].get('desc', reply['error'])}")
            if "return" in reply:
                return reply["return"]

    def events(self, events):
        self.cmd("input-send-event", events=events)

    def move(self, x, y):
        self.events([{"type": "abs", "data": {"axis": "x", "value": int(x * 32767 / W)}},
                     {"type": "abs", "data": {"axis": "y", "value": int(y * 32767 / H)}}])

    def hover(self, x, y):
        self.move(x, y)
        time.sleep(0.05)
        self.move(x + 1, y)
        time.sleep(0.1)

    def button(self, name, down):
        self.events([{"type": "btn", "data": {"down": down, "button": name}}])

    def keys(self, codes, down):
        self.events([{"type": "key", "data": {"down": down, "key": {"type": "qcode", "data": c}}}
                     for c in codes])

    def chord(self, codes):
        self.keys(codes, True)
        time.sleep(0.08)
        self.keys(list(reversed(codes)), False)


def main(argv):
    if not argv:
        raise SystemExit(__doc__)
    q = Qmp()
    what, args = argv[0], argv[1:]
    if what == "shot":
        q.cmd("screendump", filename=str(Path(args[0]).resolve()), format="png")
    elif what == "move":
        q.hover(float(args[0]), float(args[1]))
    elif what == "click":
        q.hover(float(args[0]), float(args[1]))
        name = args[2] if len(args) > 2 else "left"
        q.button(name, True)
        time.sleep(0.08)
        q.button(name, False)
    elif what == "drag":
        x1, y1, x2, y2 = map(float, args[:4])
        q.hover(x1, y1)
        q.button("left", True)
        time.sleep(0.15)
        steps = 20
        for i in range(1, steps + 1):
            q.move(x1 + (x2 - x1) * i / steps, y1 + (y2 - y1) * i / steps)
            time.sleep(0.03)
        time.sleep(0.2)
        q.button("left", False)
    elif what == "wheel":
        q.hover(float(args[0]), float(args[1]))
        for _ in range(int(args[3]) if len(args) > 3 else 1):
            q.button("wheel-" + args[2], True)
            q.button("wheel-" + args[2], False)
            time.sleep(0.05)
    elif what == "key":
        q.chord(args)
    elif what == "type":
        for ch in " ".join(args):
            code = CHARS.get(ch, ch.lower())
            q.chord(["shift", code] if ch.isupper() else [code])
            time.sleep(0.03)
    else:
        raise SystemExit(__doc__)


if __name__ == "__main__":
    main(sys.argv[1:])
