#!/usr/bin/env bash
# Вписывает в packages/claude-desktop/PKGBUILD последнюю версию Claude
# Desktop из APT-репозитория Anthropic.
#
# Цепочка доверия как у apt: InRelease подписан ключом Anthropic
# (packages/claude-desktop/anthropic.asc, отпечаток ниже; тот же ключ
# лежит на https://downloads.claude.ai/keys/claude-code.asc), в нём
# SHA256 списка Packages, в списке — SHA256 самого .deb.
#
# После него — обычный выпуск: build-packages.sh → release-repo.sh.
# Ничего не меняет, если версия та же.
#
#   --notify   только проверить и, если вышла новая версия, показать
#              уведомление (так его раз в день зовёт таймер из dev-setup.sh)
set -euo pipefail

notify=0
[[ ${1:-} == --notify ]] && notify=1

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$ROOT/packages/claude-desktop"
BASE=https://downloads.claude.ai/claude-desktop/apt/stable
FPR=31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE
LIST=main/binary-amd64/Packages

die() { echo "Ошибка: $*" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

gpg --batch --quiet --dearmor -o "$tmp/key.gpg" "$PKG/anthropic.asc"
gpg --show-keys --with-colons "$tmp/key.gpg" | grep -qx "fpr:::::::::$FPR:" \
  || die "в anthropic.asc не тот ключ."

curl -fsSL -o "$tmp/InRelease" "$BASE/dists/stable/InRelease"
gpgv --keyring "$tmp/key.gpg" --output "$tmp/Release" "$tmp/InRelease" 2>/dev/null \
  || die "подпись InRelease не сходится с ключом Anthropic."

# SHA256 списка пакетов из подписанного Release
sum="$(awk -v f="$LIST" '/^SHA256:/{s=1;next} /^[^ ]/{s=0} s && $3==f {print $1}' "$tmp/Release")"
[[ -n $sum ]] || die "в Release нет $LIST."
curl -fsSL -o "$tmp/Packages" "$BASE/dists/stable/$LIST"
echo "$sum  $tmp/Packages" | sha256sum -c --quiet - || die "список Packages не сходится с Release."

# Последняя версия и её SHA256
read -r ver deb < <(awk '/^Version:/{v=$2} /^SHA256:/{print v, $2}' "$tmp/Packages" | sort -V | tail -1)
[[ $ver =~ ^[0-9.]+$ && $deb =~ ^[0-9a-f]{64}$ ]] || die "не разобрал список Packages."

cur="$(sed -n 's/^pkgver=//p' "$PKG/PKGBUILD")"
if [[ $ver == "$cur" ]]; then
  echo "claude-desktop $cur — уже последняя."
  exit 0
fi

if [[ $notify == 1 ]]; then
  notify-send -a Sedmio -i claude-desktop "Вышел Claude Desktop $ver" \
    "В [sedmio] пока $cur. Обновить: scripts/update-claude-desktop.sh, сборка, выпуск."
  exit 0
fi

sed -i -e "s/^pkgver=.*/pkgver=$ver/" -e 's/^pkgrel=.*/pkgrel=1/' \
  -e "s/^sha256sums_x86_64=.*/sha256sums_x86_64=('$deb')/" "$PKG/PKGBUILD"
rm -f "$PKG"/claude-desktop_*_amd64.deb
echo "claude-desktop: $cur → $ver"
