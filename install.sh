#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/DaxGoon/tula.git"
MATRA_HOME="${MATRA_HOME:-$HOME/matra}"
SKILL_DIR="$HOME/.claude/skills/matra"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

usage() {
  echo "Usage: install.sh [OPTIONS]"
  echo ""
  echo "Install matra as a Claude Code skill."
  echo ""
  echo "Options:"
  echo "  --home DIR    Install directory (default: ~/matra)"
  echo "  --help        Show this help"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --home) MATRA_HOME="$2"; shift 2 ;;
    --help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

echo "Installing matra..."

# --- Prerequisites ---

install_pkg() {
  local pkg="$1"
  echo "  Installing $pkg..."
  if command -v brew &>/dev/null; then
    brew install "$pkg" 2>/dev/null
  elif command -v apt-get &>/dev/null; then
    sudo apt-get install -y "$pkg" 2>/dev/null
  elif command -v dnf &>/dev/null; then
    sudo dnf install -y "$pkg" 2>/dev/null
  elif command -v pacman &>/dev/null; then
    sudo pacman -S --noconfirm "$pkg" 2>/dev/null
  else
    echo "  Could not auto-install $pkg. Please install it manually." >&2
    return 1
  fi
}

echo ""
echo "Checking prerequisites..."

for tool in jq git python3; do
  if command -v "$tool" &>/dev/null; then
    echo "  $tool: $(command -v "$tool")"
  else
    install_pkg "$tool" || { echo "Error: $tool is required but could not be installed." >&2; exit 1; }
    echo "  $tool: installed"
  fi
done

# --- Clone or locate repo ---

if [[ -f "$SCRIPT_DIR/adapters/claude-code/SKILL.md" ]]; then
  MATRA_HOME="$SCRIPT_DIR"
  echo ""
  echo "  Source: $MATRA_HOME (local)"
elif [[ ! -f "$MATRA_HOME/adapters/claude-code/SKILL.md" ]]; then
  echo ""
  echo "  Cloning tula into $MATRA_HOME..."
  git clone "$REPO_URL" "$MATRA_HOME"
fi

if [[ ! -f "$MATRA_HOME/adapters/claude-code/SKILL.md" ]]; then
  echo "Error: matra not found at $MATRA_HOME" >&2
  exit 1
fi

# --- Link skill ---

mkdir -p "$SKILL_DIR"
ln -sf "$MATRA_HOME/adapters/claude-code/SKILL.md" "$SKILL_DIR/SKILL.md"
echo "  Skill linked: $SKILL_DIR/SKILL.md"

chmod +x "$MATRA_HOME/scripts/"*.sh
echo "  Scripts: executable"

# --- Language tools ---

echo ""
echo "  Language tools detected:"
found=0
for tool in bandit pylint flake8 mypy safety eslint tsc golangci-lint go clang-tidy cppcheck pmd checkstyle; do
  if command -v "$tool" &>/dev/null; then
    echo "    $tool"
    found=1
  fi
done
[[ $found -eq 0 ]] && echo "    (none — install language-specific tools for deeper analysis)"

echo ""
echo "Done. Type /matra in Claude Code to analyse any project."
echo ""
echo "Alternatively, install as a plugin:"
echo "  /plugin marketplace add daxgoon/tula"
echo "  /plugin install matra@daxgoon-tools"
echo ""
echo "To uninstall: bash $MATRA_HOME/uninstall.sh"
