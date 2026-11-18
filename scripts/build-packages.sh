#!/usr/bin/env bash
# Собирает все пакеты из packages/ в локальный репозиторий out/repo.
# Запускать от обычного пользователя: makepkg не работает от root.
#
# Компилируемый пакет (Calamares, несколько минут) не пересобирается,
# если эта версия уже есть в репозитории. Пакеты из одних конфигов
# собираются за секунды и пересобираются всегда.
# Пересобрать всё: FORCE=1 scripts/build-packages.sh
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
  name="$(basename "$dir")"

  compiled=0
  grep -q '^build()' "$dir/PKGBUILD" && compiled=1

  # Компилируемый пакет этой версии уже есть — не пересобираем
  if [[ $compiled == 1 && ${FORCE:-0} != 1 ]]; then
    built=1
    while read -r file; do
      [[ -f $file ]] || built=0
    done < <(cd "$dir" && PKGDEST="$REPO" makepkg --packagelist)
    if [[ $built == 1 ]]; then
      echo "==> $name: уже собран"
      continue
    fi
  fi

  echo "==> $name"
  if [[ $compiled == 1 ]]; then
    # Пакет компилируется: ставим его зависимости для сборки
    flags=(--syncdeps --noconfirm --needed)
  else
    # Пакет состоит только из конфигов и зависимостей,
    # ставить его зависимости на машину сборки не нужно.
    flags=(--nodeps)
  fi
  (cd "$dir" && PKGDEST="$REPO" makepkg --force --cleanbuild "${flags[@]}")
done

repo-add --remove "$REPO/sedmio.db.tar.gz" "$REPO"/*.pkg.tar.zst

echo
echo "Готово: $REPO"
