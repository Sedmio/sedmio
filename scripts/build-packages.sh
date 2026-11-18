#!/usr/bin/env bash
# Собирает все пакеты из packages/ в локальный репозиторий out/repo.
# Запускать от обычного пользователя: makepkg не работает от root.
#
# Компилируемый пакет (Calamares, несколько минут) не пересобирается,
# если эта версия уже есть в репозитории. Пакеты из одних конфигов
# собираются за секунды и пересобираются всегда.
# Пересобрать всё: FORCE=1 scripts/build-packages.sh
#
# Пакеты и база подписываются ключом Sedmio, если его закрытая часть есть
# в gpg этого пользователя (отпечаток — в packages/sedmio-keyring/sedmio-trusted).
# Без ключа сборка тоже работает — для ISO подпись не нужна, но выложить
# такие пакеты в [sedmio] нельзя (scripts/release-repo.sh откажется).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$ROOT/out/repo"
KEY="$(cut -d: -f1 "$ROOT/packages/sedmio-keyring/sedmio-trusted" | head -1)"

if [[ $EUID -eq 0 ]]; then
  echo "Запусти без sudo: makepkg нельзя запускать от root." >&2
  exit 1
fi

sign=()
if gpg --list-secret-keys "$KEY" >/dev/null 2>&1; then
  sign=(--sign)
  export GPGKEY="$KEY"
else
  echo "==> Нет закрытого ключа $KEY: собираю без подписи." >&2
fi
export PACKAGER="${PACKAGER:-Sedmio Linux <fsedis@yandex.ru>}"

mkdir -p "$REPO"

for dir in "$ROOT"/packages/*/; do
  [[ -f "$dir/PKGBUILD" ]] || continue
  name="$(basename "$dir")"

  compiled=0
  grep -q '^build()' "$dir/PKGBUILD" && compiled=1

  # Компилируемый пакет этой версии уже есть — не пересобираем
  if [[ $compiled == 1 && ${FORCE:-0} != 1 ]]; then
    built=1
    files=()
    while read -r file; do
      [[ -f $file ]] || built=0
      files+=("$file")
    done < <(cd "$dir" && PKGDEST="$REPO" makepkg --packagelist)
    if [[ $built == 1 ]]; then
      echo "==> $name: уже собран"
      # Собран до появления ключа — подписываем готовый файл
      if [[ ${#sign[@]} -gt 0 ]]; then
        for file in "${files[@]}"; do
          [[ -f $file.sig ]] || gpg --batch --yes -u "$KEY" --detach-sign --no-armor "$file"
        done
      fi
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
  # Старая подпись от прошлой сборки той же версии стала бы неверной
  (cd "$dir" && PKGDEST="$REPO" makepkg --packagelist) | sed 's/$/.sig/' | xargs rm -f
  (cd "$dir" && PKGDEST="$REPO" makepkg --force --cleanbuild "${flags[@]}" "${sign[@]}")
done

if [[ ${#sign[@]} -gt 0 ]]; then
  repo-add --remove --sign --key "$KEY" "$REPO/sedmio.db.tar.gz" "$REPO"/*.pkg.tar.zst
else
  # База без подписи; старая подпись базы стала бы неверной
  rm -f "$REPO"/sedmio.{db,files}{,.tar.gz}.sig
  repo-add --remove "$REPO/sedmio.db.tar.gz" "$REPO"/*.pkg.tar.zst
fi

echo
echo "Готово: $REPO"
