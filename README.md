# Tula

Code quality, security, and documentation analysis using YAML rules, bash
scripts, and LLM reasoning.

*Tula* (Sanskrit: balance, weighing scale) analyses projects across five
categories — security, reliability, performance, maintainability, and
documentation — producing a scored report on a 1000-point scale.

## Supported Languages

Python, JavaScript/TypeScript, Java, Go, C/C++

## Prerequisites

| Tool | Required | Purpose | Install |
|------|----------|---------|---------|
| `jq` | Yes | JSON processing | `brew install jq` |
| `python3` | Recommended | Tool output parsing, metrics | System default |
| `git` | Recommended | Diff analysis | System default |

Language-specific static analysis tools (bandit, eslint, etc.) are optional.
Matra auto-detects what is installed and skips missing tools gracefully. The
report notes reduced coverage when tools are unavailable.

## Quick Start

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/DaxGoon/tula/main/install.sh)
```

Install with all language tools:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/DaxGoon/tula/main/install.sh) --all-tools
```

Or pick specific languages: `--lang python`, `--lang js`, `--lang go`, `--lang java`, `--lang cpp`

## Installation

### Claude Code Plugin (recommended)

```
/plugin marketplace add daxgoon/tula
/plugin install matra@daxgoon-tools
```

### Claude Code Manual Install

```bash
git clone https://github.com/daxgoon/tula.git ~/matra
bash ~/matra/install.sh
```

This clones the repository and links the `/matra` skill into Claude Code.
After installation, type `/matra` in any project to run an analysis.

### Per-Project (team usage)

Add as a git submodule so every team member gets it on clone:

```bash
cd <your-project>
git submodule add https://github.com/daxgoon/tula.git .matra/plugin
mkdir -p .claude/skills/matra
ln -s ../../.matra/plugin/adapters/claude-code/SKILL.md .claude/skills/matra/SKILL.md
git add .matra .claude/skills/matra
git commit -m "Add matra code quality analysis"
```

Developers cloning the project run `git submodule update --init` to activate.

### GitHub Copilot

```bash
cp ~/matra/adapters/copilot/copilot-instructions.md <project>/.github/copilot-instructions.md
```

### Cursor

```bash
cp ~/matra/adapters/cursor/matra.mdc <project>/.cursor/rules/matra.mdc
```

### CI/CD Only (no LLM required)

```bash
git clone https://github.com/daxgoon/tula.git ~/matra
~/matra/scripts/ci.sh --profile default --threshold 800
```

## Uninstallation

```bash
bash ~/matra/uninstall.sh
```

This removes the Claude Code skill link. The source directory is preserved.
To fully remove: `rm -rf ~/matra`

## Usage

### Claude Code

```
/matra                        # full analysis, default profile
/matra --profile strict       # strict thresholds (900)
/matra --profile security     # security-focused (950)
/matra docs                   # documentation quality only
/matra --diff HEAD~3          # analyse changed files only
/matra --fix                  # include fix suggestions
/matra --lang python          # single language only
```

The analysis runs unattended after a single permission approval. No further
input required.

### CI/CD

```bash
~/matra/scripts/ci.sh [OPTIONS]

Options:
  --profile PROFILE     Scoring profile (default: default)
  --threshold N         Minimum pass score (default: from profile)
  --format json|text    Output format (default: json)
  --diff REF            Analyse only files changed since REF
  --output FILE         Write report to FILE
  --project-root DIR    Target project (default: current directory)
  --deterministic       Skip LLM, use jq-based scoring

Exit codes:
  0  Pass (score >= threshold, no warnings)
  1  Pass with warnings (score >= threshold, issues present)
  2  Fail (score < threshold)
  3  Tool error
```

## Scoring

| Category        | Weight | Focus |
|-----------------|--------|-------|
| Security        | 1.5x   | Vulnerabilities, secrets, injection, CVEs |
| Reliability     | 1.2x   | Bugs, crashes, type errors, resource leaks |
| Performance     | 1.0x   | Inefficiency, unnecessary copies |
| Maintainability | 0.8x   | Complexity, style, naming, duplication |
| Documentation   | 0.6x   | README, API docs, inline comments |

Severity penalties: critical (-200), high (-100), medium (-25), low (-5),
multiplied by category weight. Base score is 1000.

### Profiles

| Profile     | Pass Threshold | Description |
|-------------|----------------|-------------|
| default     | 800            | Balanced analysis |
| strict      | 900            | All checks, higher weights |
| security    | 950            | Security-focused, 3x security weight |
| performance | 850            | Performance-focused, 2x performance weight |
| fast        | 700            | Quick analysis, fast tools only |
| docs        | 700            | Documentation quality focused |

## Static Analysis Tools

| Language | Tools |
|----------|-------|
| Python | bandit, pylint, flake8, mypy, safety |
| JavaScript/TS | eslint, tsc, npm audit, semgrep |
| Java | spotbugs, pmd, checkstyle, findsecbugs, owasp-dep-check |
| Go | golangci-lint, go vet, govulncheck, staticcheck |
| C/C++ | clang-tidy, cppcheck |

All tools are optional. Install the ones relevant to your stack:

```bash
# Python
pip install bandit pylint flake8 mypy safety

# JavaScript/TypeScript
npm install -g eslint

# Go
go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest
go install golang.org/x/vuln/cmd/govulncheck@latest
go install honnef.co/go/tools/cmd/staticcheck@latest

# C/C++
brew install llvm cppcheck   # macOS
apt install clang-tidy cppcheck   # Ubuntu/Debian
```

## Extending Rules

### Project Overrides

Create `.matra/overrides.yml` in your project root:

```yaml
disable: [todo-comment, line-too-long]
severity_overrides:
  function-too-long: low
threshold_overrides:
  function-too-long:
    value: 100
profile: strict
exclude_paths: ["generated/**"]
```

### Custom Rules

Add YAML files to `.matra/rules/<language>/<category>.yml`:

```yaml
language: python
category: maintainability

patterns:
  - id: no-print
    pattern: 'print\s*\('
    message: "Use logger instead of print()"
    severity: medium
    category: maintainability
```

Rules with matching `id` fields replace base rules. New rules are appended.

### Override Priority

1. Base rules (`~/matra/rules/`) — shipped with matra
2. Project rules (`.matra/rules/`) — committed to project repo
3. Project overrides (`.matra/overrides.yml`) — disable/adjust rules
4. Personal overrides (`~/.config/matra/overrides.yml`) — developer preference

## Architecture

```
Rules (YAML)  →  Scripts (Bash)  →  LLM (Reasoning)  →  Report
   data            invocation        scoring + semantics    output
```

```
tula/
├── .claude-plugin/     Plugin manifest for Claude Code marketplace
├── rules/              25 YAML files defining checks per language
│   ├── _scoring.yml    Scoring algorithm, weights, profiles
│   ├── _categories.yml Category and severity definitions
│   ├── <language>/     4 files: security, reliability, maintainability, performance
│   └── documentation/  3 files: readme, api-docs, inline-docs
├── scripts/            8 bash scripts
│   ├── detect.sh       Language and tool detection
│   ├── scan-*.sh       Per-language scan scripts (6)
│   └── ci.sh           CI/CD wrapper with exit codes
├── skills/             Claude Code plugin skill
│   └── matra/          /matra slash command
├── adapters/           Platform-specific integration
│   ├── claude-code/    SKILL.md for manual install
│   ├── copilot/        GitHub Copilot instructions
│   └── cursor/         Cursor rules file
├── tests/              Validation and smoke tests
├── install.sh          One-command installation
├── uninstall.sh        Clean removal
└── AGENTS.md           Portable cross-tool context
```

No application code. Rules are data. Scripts are thin wrappers. The LLM
does the interpretation, scoring, and reporting.

## Updating

```bash
cd ~/matra && git pull
```

Rules, scripts, and the skill prompt are updated in place. No reinstallation
needed — the symlink from `install.sh` points to the live files.
