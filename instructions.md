# Matra Build Instructions

## Project Structure

```
matra/
├── rules/              YAML rule definitions per language and category
│   ├── _scoring.yml    Scoring algorithm, weights, profiles
│   ├── _categories.yml Category and severity definitions
│   ├── <language>/     Language-specific rules (4 files each)
│   └── documentation/  Documentation quality rules
├── scripts/            Bash scripts for tool invocation
│   ├── detect.sh       Language and tool detection
│   ├── scan-*.sh       Per-language scan scripts
│   └── ci.sh           CI/CD wrapper with exit codes
├── adapters/           LLM platform integration files
│   ├── claude-code/    SKILL.md for /matra command
│   ├── copilot/        GitHub Copilot instructions
│   └── cursor/         Cursor rules file
├── tests/              Validation and smoke tests
└── AGENTS.md           Portable cross-tool context
```

## Implementation Specs

### Rule Files
- Format: YAML
- Schema: tools (static tool mappings), patterns (regex), thresholds (metrics),
  semantic (LLM-evaluated guidance)
- Convention: one file per category per language
- IDs: `LANG-CAT-NNN` format (e.g., PY-SEC-001)

### Bash Scripts
- Shebang: `#!/usr/bin/env bash`
- Flags: `set -euo pipefail`
- Input: `--project-root PATH` and `--files FILE...`
- Output: JSON to stdout, diagnostics to stderr
- Tool checks: `command -v`, skip silently if unavailable

### Scoring
- Defined entirely in `rules/_scoring.yml`
- No scoring logic in bash scripts
- LLM applies the algorithm; ci.sh has a deterministic fallback

## Coding Standards

- No Python code in this project
- Shell scripts checked with shellcheck
- YAML validated with yamllint or python3 yaml.safe_load
- British English in all user-facing text
- No comments unless logic is non-obvious

## Testing

```bash
# Validate all rule files parse correctly
bash tests/validate-rules.sh

# Smoke test scan scripts against fixtures
bash tests/test-scripts.sh

# Verify scoring calculations
bash tests/test-scoring.sh
```

## Installation

### Claude Code
```bash
git clone <repo> ~/matra
# Skill auto-discovered from adapters/claude-code/SKILL.md
# Usage: /matra
```

### CI/CD
```bash
~/matra/scripts/ci.sh --profile default --threshold 800
```
