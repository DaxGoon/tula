#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/DaxGoon/tula.git"
TULA_HOME="${TULA_HOME:-$HOME/tula}"
SKILL_DIR="$HOME/.claude/skills/tula"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

usage() {
  echo "Usage: install.sh [OPTIONS]"
  echo ""
  echo "Install tula as a Claude Code skill."
  echo ""
  echo "Options:"
  echo "  --home DIR      Install directory (default: ~/tula)"
  echo "  --all-tools     Install all supported language tools"
  echo "  --lang LANG     Install tools for specific language (python|js|go|java|cpp)"
  echo "  --help          Show this help"
}

INSTALL_ALL=false
INSTALL_LANGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --home) TULA_HOME="$2"; shift 2 ;;
    --all-tools) INSTALL_ALL=true; shift ;;
    --lang) INSTALL_LANGS+=("$2"); shift 2 ;;
    --help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

echo "Installing tula..."

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
  TULA_HOME="$SCRIPT_DIR"
  echo ""
  echo "  Source: $TULA_HOME (local)"
elif [[ ! -f "$TULA_HOME/adapters/claude-code/SKILL.md" ]]; then
  echo ""
  echo "  Cloning tula into $TULA_HOME..."
  git clone "$REPO_URL" "$TULA_HOME"
fi

if [[ ! -f "$TULA_HOME/adapters/claude-code/SKILL.md" ]]; then
  echo "Error: tula not found at $TULA_HOME" >&2
  exit 1
fi

# --- Link skill ---

mkdir -p "$SKILL_DIR"
ln -sf "$TULA_HOME/adapters/claude-code/SKILL.md" "$SKILL_DIR/SKILL.md"
echo "  Skill linked: $SKILL_DIR/SKILL.md"

chmod +x "$TULA_HOME/scripts/"*.sh
echo "  Scripts: executable"

# --- Language tools ---

wants_lang() {
  [[ "$INSTALL_ALL" == true ]] && return 0
  for l in "${INSTALL_LANGS[@]+"${INSTALL_LANGS[@]}"}"; do
    [[ "$l" == "$1" ]] && return 0
  done
  return 1
}

pip_install() {
  if command -v uv &>/dev/null; then
    uv tool install "$@" 2>/dev/null || uv pip install --system "$@" 2>/dev/null
  elif command -v pipx &>/dev/null; then
    for pkg in "$@"; do pipx install "$pkg" 2>/dev/null || true; done
  elif command -v pip3 &>/dev/null; then
    pip3 install --user "$@" 2>/dev/null
  elif command -v pip &>/dev/null; then
    pip install --user "$@" 2>/dev/null
  else
    echo "    No pip/pipx/uv found — skipping Python tools" >&2
    return 1
  fi
}

if wants_lang python; then
  echo ""
  echo "  Installing Python tools..."
  pip_install ruff bandit mypy safety 2>/dev/null && echo "    ruff bandit mypy safety" || true
fi

if wants_lang js; then
  echo ""
  echo "  Installing JavaScript/TypeScript tools..."
  if command -v npm &>/dev/null; then
    npm install -g eslint typescript 2>/dev/null && echo "    eslint tsc" || true
  else
    echo "    npm not found — skipping JS tools"
  fi
fi

if wants_lang go; then
  echo ""
  echo "  Installing Go tools..."
  if command -v go &>/dev/null; then
    go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest 2>/dev/null && echo "    golangci-lint" || true
    go install golang.org/x/vuln/cmd/govulncheck@latest 2>/dev/null && echo "    govulncheck" || true
    go install honnef.co/go/tools/cmd/staticcheck@latest 2>/dev/null && echo "    staticcheck" || true
  else
    echo "    go not found — skipping Go tools"
  fi
fi

if wants_lang java; then
  echo ""
  echo "  Installing Java tools..."
  if command -v brew &>/dev/null; then
    brew install pmd checkstyle spotbugs 2>/dev/null && echo "    pmd checkstyle spotbugs" || true
  elif command -v apt-get &>/dev/null; then
    sudo apt-get install -y pmd 2>/dev/null && echo "    pmd" || true
  else
    echo "    Install pmd, checkstyle, spotbugs manually"
  fi
fi

if wants_lang cpp; then
  echo ""
  echo "  Installing C/C++ tools..."
  if command -v brew &>/dev/null; then
    brew install llvm cppcheck 2>/dev/null && echo "    clang-tidy cppcheck" || true
  elif command -v apt-get &>/dev/null; then
    sudo apt-get install -y clang-tidy cppcheck 2>/dev/null && echo "    clang-tidy cppcheck" || true
  elif command -v dnf &>/dev/null; then
    sudo dnf install -y clang-tools-extra cppcheck 2>/dev/null && echo "    clang-tidy cppcheck" || true
  else
    echo "    Install clang-tidy and cppcheck manually"
  fi
fi

echo ""
echo "  Language tools available:"
found=0
for tool in ruff bandit mypy safety eslint tsc golangci-lint govulncheck staticcheck clang-tidy cppcheck pmd checkstyle spotbugs; do
  if command -v "$tool" &>/dev/null; then
    printf "    %-20s %s\n" "$tool" "$(command -v "$tool")"
    found=1
  fi
done
[[ $found -eq 0 ]] && echo "    (none — run with --all-tools or --lang <lang> to install)"

echo ""
echo "Done. Type /tula in Claude Code to analyse any project."
echo ""
echo "Alternatively, install as a plugin:"
echo "  /plugin marketplace add daxgoon/tula"
echo "  /plugin install tula@daxgoon-tools"
echo ""
echo "To uninstall: bash $TULA_HOME/uninstall.sh"
