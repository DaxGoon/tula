# Matra Design Document

## Objective

Replace a ~1800-line Python code quality application (PyCC) with a lightweight,
LLM-native analysis tool that uses YAML rules, bash scripts, and LLM reasoning.
Extend coverage to JavaScript/TypeScript, Java, Go, and documentation quality.

## Technical Specification

### Architecture

```
Rules (YAML)  →  Scripts (Bash)  →  LLM (Skill/Prompt)  →  Report
   data            hands              brain                 output
```

- **Rules are data**: YAML files define what to check, severity mappings, patterns,
  and thresholds. No code. Anyone can extend by adding a YAML file.
- **Scripts are thin**: Bash wrappers invoke static tools and emit normalised JSON.
  ~50-80 lines each. No scoring logic.
- **LLM does the thinking**: Scoring, interpretation, semantic analysis, and
  reporting happen in the LLM's reasoning guided by the skill prompt.

### Why Not a Python Application

| Concern | PyCC (Python) | Matra (YAML+Bash+LLM) |
|---------|---------------|------------------------|
| Adding a rule | Edit Python class, handle imports | Add YAML entry |
| Adding a language | New Python module, register | New YAML dir + bash script |
| Scoring logic | Hardcoded in ScoringEngine | Configurable in _scoring.yml |
| Semantic analysis | Not possible | LLM evaluates guidance |
| Dependencies | click, jinja2, pyyaml, gitpython, rich | jq (bash), python3 (optional) |
| Report generation | 400 lines of Python | LLM produces natively |
| Installation | pip install + venv | git clone |

### Scoring Algorithm

Ported exactly from PyCC. See `rules/_scoring.yml` for the full specification.

Base 1000 → per-issue penalties (severity × category weight) → complexity
penalties → file weighting → project adjustments (consistency bonus, critical
overage) → final score clamped to [0, 1000].

### Rule Check Types

| Type | Evaluated By | Use Case |
|------|-------------|----------|
| `tool` | Bash scripts → static tool | Anything bandit/eslint/pmd detect |
| `pattern` | Regex (bash grep or LLM) | Secrets, unsafe functions, TODOs |
| `semantic` | LLM reasoning | Doc quality, misleading comments, design smells |
| `threshold` | Metrics comparison | Function length, complexity, nesting |

### Override Mechanism

Three tiers, highest priority wins:
1. Base rules (`~/matra/rules/`)
2. Project overrides (`.matra/rules/` + `.matra/overrides.yml`)
3. Personal overrides (`~/.config/matra/overrides.yml`)

### Delivery Mechanisms

| Platform | Mechanism | File |
|----------|-----------|------|
| Claude Code | Skill (/matra) | `adapters/claude-code/SKILL.md` |
| GitHub Copilot | Custom instructions | `adapters/copilot/copilot-instructions.md` |
| Cursor | Rules file | `adapters/cursor/matra.mdc` |
| Any (portable) | AGENTS.md | `AGENTS.md` |
| CI/CD (no LLM) | Bash script | `scripts/ci.sh` |

## Solution Design

### Zero-Input UX

The skill requests all permissions upfront in a single batch. Auto-detects
language, profile, and tools. No prompts during analysis. The user types
`/matra` and gets a report.

### Languages and Tools

| Language | Static Tools | Pattern Checks | Semantic Checks |
|----------|-------------|----------------|-----------------|
| Python | bandit, pylint, flake8, mypy, safety | secrets, eval, exec | doc quality |
| JavaScript/TS | eslint, tsc, npm audit | eval, innerHTML, secrets | doc quality |
| Java | spotbugs, pmd, checkstyle | SQL injection, secrets | doc quality |
| Go | golangci-lint, go vet, govulncheck, staticcheck | secrets, unsafe | doc quality |
| C/C++ | clang-tidy, cppcheck | unsafe functions, format strings | doc quality |
| Documentation | scan-docs.sh (file checks, coverage) | — | completeness, accuracy |
