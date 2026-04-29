#!/usr/bin/env bash
set -euo pipefail

SKILL_DIR="$HOME/.claude/skills/matra"

echo "Uninstalling matra..."

# Remove Claude Code skill link
if [[ -d "$SKILL_DIR" ]]; then
  rm -rf "$SKILL_DIR"
  echo "  Removed skill: $SKILL_DIR"
else
  echo "  Skill not found at $SKILL_DIR (already removed)"
fi

echo ""
echo "Done. The /matra command is no longer available in Claude Code."
echo ""
echo "The matra source directory has not been removed."
echo "To fully remove, delete the directory manually:"
echo "  rm -rf $(cd "$(dirname "$0")" && pwd)"
