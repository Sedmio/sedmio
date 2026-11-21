#!/bin/bash
# Запуск Claude Desktop. В сеансе Wayland просит у Electron Wayland:
# сам он выбирает X11, то есть XWayland. Свой --ozone-platform в
# аргументах или в ~/.config/claude-desktop-flags.conf (флаги через
# пробел, # — комментарий) это отменяет.
set -euo pipefail

flags=()
conf="${XDG_CONFIG_HOME:-$HOME/.config}/claude-desktop-flags.conf"
if [[ -r $conf ]]; then
  while IFS= read -r line || [[ -n $line ]]; do
    line="${line%%#*}"
    read -r -a words <<<"$line"
    flags+=("${words[@]}")
  done <"$conf"
fi

platform=()
if [[ -n ${WAYLAND_DISPLAY:-} || ${XDG_SESSION_TYPE:-} == wayland ]]; then
  platform=(--ozone-platform=wayland)
  for f in "${flags[@]}" "$@"; do
    [[ $f == --ozone-platform=* || $f == --ozone-platform-hint=* ]] && platform=()
  done
fi

exec /usr/lib/claude-desktop/claude-desktop "${platform[@]}" "${flags[@]}" "$@"
