#!/usr/bin/env bash
# Готовит установленную Sedmio как машину разработки самой Sedmio:
# инструменты сборки пакетов и ISO, виртуалка, gh, ключ подписи, Claude Code.
#
#   scripts/dev-setup.sh                      # всё, кроме ключа подписи
#   scripts/dev-setup.sh /путь/к/ключу        # папка с sedmio-private-key.asc
#
# Запускать от своего пользователя (не через sudo): ключ подписи, gh и
# Claude Code ставятся ему. sudo скрипт попросит сам. Повторный запуск
# ничего не ломает — сделанное пропускается.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KEY="$(cut -d: -f1 "$ROOT/packages/sedmio-keyring/sedmio-trusted" | head -1)"

die() { echo "Ошибка: $*" >&2; exit 1; }
step() { echo; echo "==> $*"; }

[[ $EUID -ne 0 ]] || die "запусти без sudo, от своего пользователя."

# ---------- пакеты

# base-devel, git        — makepkg (build-packages.sh)
# archiso, grub, шрифт   — build-iso.sh (меню загрузки GRUB со шрифтом)
# qemu-desktop, OVMF     — run-vm.sh, socat — управление виртуалкой
# github-cli             — release-repo.sh
#
# Сначала обновление: правила NoExtract в sedmio-settings должны быть
# свежими до того, как распакуются grub и остальные (pacman читает их
# в начале операции).
step "Обновляю систему"
sudo pacman -Syu --noconfirm

step "Ставлю инструменты сборки"
sudo pacman -S --needed --noconfirm \
  base-devel git archiso grub ttf-jetbrains-mono \
  qemu-desktop edk2-ovmf socat rsync \
  github-cli

# Без en@quot у GRUB не собирается ISO. Его могли не распаковать старые
# правила NoExtract (sedmio-settings до 0.1.0-5) — тогда ставим grub заново.
if [[ ! -f /usr/share/locale/en@quot/LC_MESSAGES/grub.mo ]]; then
  sudo pacman -S --noconfirm grub
fi

# ---------- git

if [[ -z $(git config --global user.name || true) ]]; then
  step "Git: имя и почта для коммитов"
fi
if [[ -z $(git config --global user.name || true) && ! -t 0 ]]; then
  echo "Пропущено: нет терминала. Потом: git config --global user.name / user.email"
elif [[ -z $(git config --global user.name || true) ]]; then
  read -rp "Имя: " name
  read -rp "Почта: " email
  git config --global user.name "$name"
  git config --global user.email "$email"
fi

# ---------- ключ подписи [sedmio]

step "Ключ подписи пакетов"
if gpg --list-secret-keys "$KEY" >/dev/null 2>&1; then
  echo "Уже есть: $KEY"
elif [[ -n ${1:-} ]]; then
  [[ -f $1/sedmio-private-key.asc ]] || die "нет файла $1/sedmio-private-key.asc"
  gpg --batch --import "$1/sedmio-private-key.asc"
  gpg --list-secret-keys "$KEY" >/dev/null 2>&1 \
    || die "в $1/sedmio-private-key.asc не тот ключ: нужен $KEY."
  # Ключ свой: полное доверие, иначе gpg предупреждает при каждой подписи
  echo "$KEY:6:" | gpg --batch --import-ownertrust
  echo "Восстановлен: $KEY"
else
  echo "Не задан. Без него пакеты собираются, но выложить их в [sedmio] нельзя."
  echo "Потом: scripts/dev-setup.sh /путь/к/папке/с/ключом"
fi

# ---------- GitHub

step "Вход в GitHub (для release-repo.sh)"
if gh auth status >/dev/null 2>&1; then
  echo "Уже выполнен."
elif [[ -t 0 ]]; then
  gh auth login --git-protocol https --web
  gh auth setup-git
else
  echo "Пропущен: нет терминала. Потом: gh auth login"
fi

# ---------- Claude Code

step "Claude Code"
if command -v claude >/dev/null || [[ -x $HOME/.local/bin/claude ]]; then
  echo "Уже стоит."
else
  # Официальный установщик: кладёт claude в ~/.local/bin и сам обновляет
  curl -fsSL https://claude.ai/install.sh | bash
fi
# ~/.local/bin в Arch по умолчанию не входит в PATH
if ! grep -qs 'HOME/.local/bin' "$HOME/.bashrc"; then
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
  echo "Добавил ~/.local/bin в PATH (~/.bashrc): открой новый терминал."
fi

# ---------- новые версии Claude Desktop

# [sedmio] несёт пакет claude-desktop из .deb Anthropic. Сам он не
# обновляется: раз в день таймер проверяет их APT-репозиторий и
# уведомляет, если пора выпустить новую версию.
step "Проверка новых версий Claude Desktop"
units="$HOME/.config/systemd/user"
mkdir -p "$units"
cat > "$units/sedmio-claude-desktop-check.service" <<EOF
[Unit]
Description=Проверка новой версии Claude Desktop для [sedmio]
After=network-online.target

[Service]
Type=oneshot
ExecStart=$ROOT/scripts/update-claude-desktop.sh --notify
EOF
cat > "$units/sedmio-claude-desktop-check.timer" <<'EOF'
[Unit]
Description=Раз в день: новая версия Claude Desktop для [sedmio]

[Timer]
OnCalendar=daily
OnStartupSec=10min
Persistent=true
RandomizedDelaySec=1h

[Install]
WantedBy=timers.target
EOF
systemctl --user daemon-reload
systemctl --user enable --now sedmio-claude-desktop-check.timer

echo
echo "Готово. Дальше:"
echo "  cd $ROOT && claude"
echo "Сборка и выпуск — в README.md, раздел «Выпуск обновлений»."
