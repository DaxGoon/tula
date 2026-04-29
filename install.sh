#!/usr/bin/env bash
set -euo pipefail

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

# If running from within the repo, use this directory
if [[ -f "$SCRIPT_DIR/adapters/claude-code/SKILL.md" ]]; then
  MATRA_HOME="$SCRIPT_DIR"
  echo "  Source: $MATRA_HOME"
fi

# Verify matra directory exists and has required files
if [[ ! -f "$MATRA_HOME/adapters/claude-code/SKILL.md" ]]; then
  echo "Error: matra not found at $MATRA_HOME" >&2
  echo "Clone the repository first: git clone <repo-url> $MATRA_HOME" >&2
  exit 1
fi

# Link Claude Code skill
mkdir -p "$SKILL_DIR"
ln -sf "$MATRA_HOME/adapters/claude-code/SKILL.md" "$SKILL_DIR/SKILL.md"
echo "  Skill linked: $SKILL_DIR/SKILL.md -> $MATRA_HOME/adapters/claude-code/SKILL.md"

# Make scripts executable
chmod +x "$MATRA_HOME/scripts/"*.sh
echo "  Scripts: executable"

# Check prerequisites
missing=()
command -v jq &>/dev/null || missing+=("jq")
command -v python3 &>/dev/null || missing+=("python3")
command -v git &>/dev/null || missing+=("git")

if [[ ${#missing[@]} -gt 0 ]]; then
  echo ""
  echo "  Missing recommended tools: ${missing[*]}"
  echo "  Install with: brew install ${missing[*]}"
fi

# Show available language tools
echo ""
echo "  Language tools detected:"
for tool in bandit pylint flake8 mypy safety eslint tsc golangci-lint go clang-tidy cppcheck pmd checkstyle; do
  if command -v "$tool" &>/dev/null; then
    echo "    $tool"
  fi
done

echo ""
echo "Done. Type /matra in Claude Code to analyse any project."
echo ""
echo "Alternatively, install as a plugin:"
echo "  /plugin marketplace add daxgoon/tula"
echo "  /plugin install matra@daxgoon-tools"
echo ""
echo "To uninstall: bash $MATRA_HOME/uninstall.sh"
