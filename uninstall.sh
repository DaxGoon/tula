#!/usr/bin/env bash
set -euo pipefail

SKILL_DIR="$HOME/.claude/skills/tula"

echo "Uninstalling tula..."

# Remove Claude Code skill link
if [[ -d "$SKILL_DIR" ]]; then
  rm -rf "$SKILL_DIR"
  echo "  Removed skill: $SKILL_DIR"
else
  echo "  Skill not found at $SKILL_DIR (already removed)"
fi

echo ""
echo "Done. The /tula command is no longer available in Claude Code."
echo ""
echo "The tula source directory has not been removed."
echo "To fully remove, delete the directory manually:"
echo "  rm -rf $(cd "$(dirname "$0")" && pwd)"
