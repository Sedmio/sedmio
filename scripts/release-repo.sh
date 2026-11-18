#!/usr/bin/env bash
# Выкладывает собранный out/repo в сетевой репозиторий [sedmio] — файлы
# выпуска x86_64 на GitHub. Оттуда установленные системы получают
# обновления пакетов Sedmio через pacman -Syu:
#
#   [sedmio]
#   Server = https://github.com/Sedmio/sedmio/releases/download/$arch
#
# Порядок выпуска: build-packages.sh → release-repo.sh → build-iso.sh.
# Тогда на образе лежат те же самые файлы, что и в сети.
#
# Пакет той же версии, что уже в сети, заново не загружается: в out/repo
# возвращается прежний файл из сети (его уже знают установленные системы
# и их кэш pacman). Если содержимое у пакетов разное, значит пакет
# изменили, не подняв pkgrel, и до систем это изменение не дойдёт, —
# тогда скрипт ничего не выкладывает и говорит, какой пакет поправить.
#
# Запускать от того же пользователя, что и build-packages.sh (нужен его
# ключ подписи). Нужен gh (github-cli) со входом в GitHub: gh auth login
# или переменная GH_TOKEN.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$ROOT/out/repo"
KEY="$(cut -d: -f1 "$ROOT/packages/sedmio-keyring/sedmio-trusted" | head -1)"
GH_REPO=Sedmio/sedmio
TAG=x86_64
BASE="https://github.com/$GH_REPO/releases/download/$TAG"

die() { echo "Ошибка: $*" >&2; exit 1; }

[[ $EUID -ne 0 ]] || die "запусти без sudo, от пользователя с ключом подписи."
command -v gh >/dev/null || die "нет gh: pacman -S github-cli"
gh auth status >/dev/null 2>&1 || die "gh не вошёл в GitHub: gh auth login (или GH_TOKEN)."
gpg --list-secret-keys "$KEY" >/dev/null 2>&1 || die "нет закрытого ключа $KEY."
[[ -f $REPO/sedmio.db.tar.gz ]] || die "нет $REPO. Сначала: scripts/build-packages.sh"

shopt -s nullglob
pkgs=("$REPO"/*.pkg.tar.zst)
[[ ${#pkgs[@]} -gt 0 ]] || die "в $REPO нет пакетов."

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Подпись проверяем ключом из пакета sedmio-keyring, а не связкой gpg
# пользователя: так же её будет проверять pacman на установленной системе.
gpg --batch --quiet --homedir "$tmp/gnupg" --import \
  "$ROOT/packages/sedmio-keyring/sedmio.gpg" 2>/dev/null
verify() {
  [[ -f $1.sig ]] || die "$(basename "$1"): нет подписи. Пересобери: scripts/build-packages.sh"
  gpg --batch --quiet --homedir "$tmp/gnupg" --verify "$1.sig" "$1" 2>/dev/null \
    || die "$(basename "$1"): подпись не сходится с ключом из sedmio-keyring."
}

# Содержимое пакета без того, что меняется при каждой сборке
# (дата сборки, сборщик, время файлов, сведения о машине сборки).
content() {
  bsdtar -xOf "$1" .PKGINFO | grep -v '^\(builddate\|packager\) = '
  bsdtar -xOf "$1" .MTREE | gzip -dc \
    | grep -v '^\./\.\(PKGINFO\|BUILDINFO\) ' | sed 's/ time=[0-9.]*//'
}

# ---------- что уже лежит в сети

if ! gh release view "$TAG" -R "$GH_REPO" >/dev/null 2>&1; then
  echo "==> Создаю выпуск $TAG"
  gh release create "$TAG" -R "$GH_REPO" --latest=false \
    --title "Репозиторий пакетов Sedmio (x86_64)" \
    --notes "Пакеты Sedmio Linux для pacman. Файлы обновляет scripts/release-repo.sh.

Подключение в /etc/pacman.conf (установщик Sedmio делает это сам):

\`\`\`
[sedmio]
Server = https://github.com/$GH_REPO/releases/download/\$arch
\`\`\`

Пакеты и база подписаны ключом из пакета sedmio-keyring." >/dev/null
fi

mapfile -t assets < <(gh release view "$TAG" -R "$GH_REPO" --json assets -q '.assets[].name')
declare -A online=()   # имя файла пакета → sha256 из сетевой базы
if printf '%s\n' "${assets[@]}" | grep -qx sedmio.db; then
  curl -fsSL "$BASE/sedmio.db" -o "$tmp/online.db"
  mkdir "$tmp/online"
  bsdtar -xf "$tmp/online.db" -C "$tmp/online"
  for desc in "$tmp"/online/*/desc; do
    file="$(awk '/^%FILENAME%$/ { getline; print }' "$desc")"
    online[$file]="$(awk '/^%SHA256SUM%$/ { getline; print }' "$desc")"
  done
fi

# ---------- пакеты той же версии, что в сети

failed=0 replaced=0
for pkg in "${pkgs[@]}"; do
  file="$(basename "$pkg")"
  [[ -n ${online[$file]:-} ]] || continue
  [[ $(sha256sum < "$pkg" | cut -d' ' -f1) == "${online[$file]}" ]] && continue

  curl -fsSL "$BASE/$file" -o "$tmp/$file"
  curl -fsSL "$BASE/$file.sig" -o "$tmp/$file.sig"
  if [[ $(content "$pkg") != "$(content "$tmp/$file")" ]]; then
    name="$(bsdtar -xOf "$pkg" .PKGINFO | awk -F' = ' '$1 == "pkgbase" { print $2 }')"
    echo "$file: содержимое изменилось, а версия та же, что в сети." >&2
    echo "  Подними pkgrel в packages/$name/PKGBUILD и пересобери пакеты." >&2
    failed=1
    continue
  fi
  echo "==> $file: в сети тот же пакет, беру его файл"
  mv -f "$tmp/$file" "$tmp/$file.sig" "$REPO/"
  replaced=1
done
(( failed == 0 )) || die "ничего не выложено."

if (( replaced )); then
  repo-add --quiet --sign --key "$KEY" "$REPO/sedmio.db.tar.gz" "${pkgs[@]}"
fi

for pkg in "${pkgs[@]}"; do verify "$pkg"; done
verify "$REPO/sedmio.db.tar.gz"
verify "$REPO/sedmio.files.tar.gz"

# ---------- загрузка

# База — настоящими файлами под именами, которые спрашивает pacman
# (в out/repo sedmio.db — ссылка на sedmio.db.tar.gz).
mkdir "$tmp/up"
for db in db files; do
  cp "$REPO/sedmio.$db.tar.gz" "$tmp/up/sedmio.$db"
  cp "$REPO/sedmio.$db.tar.gz.sig" "$tmp/up/sedmio.$db.sig"
done

has_asset() { printf '%s\n' "${assets[@]}" | grep -qxF "$1"; }

# Сначала пакеты, потом база: база не должна ссылаться на файлы,
# которых ещё нет.
upload=()
for pkg in "${pkgs[@]}"; do
  file="$(basename "$pkg")"
  if ! has_asset "$file" || [[ -z ${online[$file]:-} ]] || ! has_asset "$file.sig"; then
    upload+=("$pkg" "$pkg.sig")
  fi
done
if [[ ${#upload[@]} -gt 0 ]]; then
  echo "==> Загружаю пакеты: $(( ${#upload[@]} / 2 ))"
  gh release upload "$TAG" -R "$GH_REPO" --clobber "${upload[@]}"
else
  echo "==> Новых пакетов нет"
fi
echo "==> Загружаю базу"
gh release upload "$TAG" -R "$GH_REPO" --clobber "$tmp"/up/*

# Старые версии — после базы, которая на них уже не ссылается
keep=(sedmio.db sedmio.db.sig sedmio.files sedmio.files.sig)
for pkg in "${pkgs[@]}"; do keep+=("$(basename "$pkg")" "$(basename "$pkg").sig"); done
for asset in "${assets[@]}"; do
  if ! printf '%s\n' "${keep[@]}" | grep -qxF "$asset"; then
    echo "==> Удаляю старый файл: $asset"
    gh release delete-asset "$TAG" "$asset" -R "$GH_REPO" --yes
  fi
done

# ---------- проверка: в сети то же, что здесь

curl -fsSL "$BASE/sedmio.db" -o "$tmp/check.db"
cmp -s "$tmp/check.db" "$REPO/sedmio.db.tar.gz" \
  || die "база в сети не совпадает с out/repo (кэш GitHub?) — запусти ещё раз."

echo
echo "Готово: $BASE"
echo "Пакеты: ${#pkgs[@]}. Теперь можно собирать ISO: sudo scripts/build-iso.sh"
