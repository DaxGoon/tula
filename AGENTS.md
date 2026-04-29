# Tula — Code Quality Analysis

Tula analyses code quality, security, and documentation using YAML rules,
bash scripts, and LLM reasoning. It produces a scored report on a 1000-point
scale across five categories: security, reliability, performance,
maintainability, and documentation.

## Supported Languages

Python, JavaScript/TypeScript, Java, Go, C/C++.

## How It Works

1. `scripts/detect.sh` identifies project languages and available tools
2. `scripts/scan-<language>.sh` runs static analysis tools, emits JSON
3. `rules/<language>/*.yml` define severity mappings, patterns, and thresholds
4. `rules/_scoring.yml` defines the scoring algorithm and profiles
5. The LLM maps findings to rules, evaluates semantic checks, calculates
   scores, and produces the report

## Quick Start

```
# In Claude Code:
/tula

# With options:
/tula --profile strict
/tula --diff HEAD~3
/tula docs
```

## Scoring

- Base score: 1000
- Penalties per issue: severity_penalty * category_weight
- Categories: security (1.5x), reliability (1.2x), performance (1.0x),
  maintainability (0.8x), documentation (0.6x)
- Profiles: default (800), strict (900), security (950), performance (850),
  fast (700), docs (700)

## Extending Rules

Add project-specific rules in `.tula/rules/<language>/<category>.yml`.
Override settings in `.tula/overrides.yml`:

```yaml
disable: [todo-comment]
severity_overrides:
  function-too-long: low
profile: strict
```

## CI/CD

```bash
~/tula/scripts/ci.sh --profile default --threshold 800
# Exit: 0=pass, 1=warn, 2=fail, 3=error
```
