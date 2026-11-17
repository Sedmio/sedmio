#!/usr/bin/env bash
# Собирает все пакеты из packages/ в локальный репозиторий out/repo.
# Запускать от обычного пользователя: makepkg не работает от root.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$ROOT/out/repo"

if [[ $EUID -eq 0 ]]; then
  echo "Запусти без sudo: makepkg нельзя запускать от root." >&2
  exit 1
fi

mkdir -p "$REPO"

for dir in "$ROOT"/packages/*/; do
  [[ -f "$dir/PKGBUILD" ]] || continue
  echo "==> $(basename "$dir")"
  # --nodeps: пакеты состоят только из конфигов и зависимостей,
  # ставить их зависимости на машину сборки не нужно.
  (cd "$dir" && PKGDEST="$REPO" makepkg --force --cleanbuild --nodeps)
done

repo-add --remove "$REPO/sedmio.db.tar.gz" "$REPO"/*.pkg.tar.zst

echo
echo "Готово: $REPO"
