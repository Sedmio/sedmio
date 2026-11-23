#!/usr/bin/env bash
# Выполняет команду внутри виртуалки из run-vm.sh через гостевой агент QEMU
# (qemu-guest-agent есть в live-образе) и печатает её вывод.
#
#   scripts/vm-exec.sh 'journalctl -b -p err --no-pager | tail'
#   scripts/vm-exec.sh --user 'kscreen-doctor -o'   # от пользователя (uid 1000), в его сеансе
#   scripts/vm-exec.sh --push локальный_файл /путь/в/виртуалке
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOCK="$ROOT/out/vm/qga.sock"

mode=exec
case "${1:-}" in
  --user) mode=user; shift ;;
  --push) mode=push; shift ;;
esac

if [[ $mode == push ]]; then
  src="${1:?нужен локальный файл}"; dst="${2:?нужен путь в виртуалке}"
  arg1="$src"; arg2="$dst"
else
  cmd="${1:?нужна команда}"
  if [[ $mode == user ]]; then
    # Окружение сеанса первого пользователя (uid 1000: live на образе,
    # тот, кого создал установщик, — на диске): Wayland, D-Bus, тема KDE.
    # Переменных из environment.d здесь нет — программу, которой они
    # нужны (окно выбора файла через портал), запускать в сеансе:
    #   vm-exec.sh --user 'systemd-run --user --collect программа'
    cmd="runuser -u \$(id -nu 1000) -- env XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-1 \
DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus QT_QPA_PLATFORM=wayland \
XDG_CURRENT_DESKTOP=KDE HOME=\$(getent passwd 1000 | cut -d: -f6) \
LANG=ru_RU.UTF-8 bash -c $(printf '%q' "$cmd")"
  fi
  arg1="$cmd"; arg2=""
fi

exec python3 - "$SOCK" "$mode" "$arg1" "$arg2" <<'PY'
import base64, json, socket, sys, time

sock_path, mode, arg1, arg2 = sys.argv[1:5]
s = socket.socket(socket.AF_UNIX)
s.connect(sock_path)
f = s.makefile("rw")

def call(execute, **arguments):
    f.write(json.dumps({"execute": execute, "arguments": arguments}) + "\n")
    f.flush()
    while True:
        reply = json.loads(f.readline())
        if "return" in reply or "error" in reply:
            if "error" in reply:
                sys.exit(f"агент: {reply['error']}")
            return reply["return"]

call("guest-sync", id=4242)

if mode == "push":
    data = open(arg1, "rb").read()
    h = call("guest-file-open", path=arg2, mode="wb")
    for i in range(0, len(data), 48 * 1024):
        call("guest-file-write", handle=h, **{"buf-b64": base64.b64encode(data[i:i + 48 * 1024]).decode()})
    call("guest-file-close", handle=h)
    # Новый файл агент создаёт с правами 666: ставим как у своего, но без
    # записи для группы и остальных (пакеты ставят 644/755). Иначе systemd
    # ругается на drop-in, а ВМ расходится с настоящей установкой.
    import os
    perm = os.stat(arg1).st_mode & 0o755
    pid = call("guest-exec", path="/bin/chmod", arg=[format(perm, "o"), "--", arg2])["pid"]
    while not call("guest-exec-status", pid=pid).get("exited"):
        time.sleep(0.1)
    print(f"{arg1} → {arg2} ({len(data)} байт)")
    sys.exit(0)

pid = call("guest-exec", path="/bin/bash", arg=["-c", arg1], **{"capture-output": True})["pid"]
while True:
    st = call("guest-exec-status", pid=pid)
    if st.get("exited"):
        break
    time.sleep(0.3)
for key, stream in (("out-data", sys.stdout), ("err-data", sys.stderr)):
    if key in st:
        stream.write(base64.b64decode(st[key]).decode("utf-8", "replace"))
sys.exit(st.get("exitcode", 0))
PY
