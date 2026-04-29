# Contributing to Tula

Contributions are welcome. This guide covers the essentials.

## Getting Started

1. Fork and clone the repository
2. Run the test suite to confirm a clean baseline:
   ```bash
   bash tests/validate-rules.sh
   bash tests/test-scripts.sh
   bash tests/test-scoring.sh
   ```

## Submitting Changes

1. Create a feature branch from `main`
2. Make your changes
3. Ensure all tests pass
4. Submit a pull request with a clear description of what and why

## Adding Rules

Rules are YAML files in `rules/<language>/<category>.yml`. Each rule requires:

- `id` — unique identifier
- `pattern` — regex to match
- `message` — human-readable explanation
- `severity` — one of: critical, high, medium, low
- `category` — one of: security, reliability, performance, maintainability

Run `bash tests/validate-rules.sh` to verify rule schema compliance.

## Adding Language Support

1. Create rule files in `rules/<language>/`
2. Add a scan script at `scripts/scan-<language>.sh`
3. Add test fixtures in `tests/fixtures/`
4. Update `scripts/detect.sh` to recognise the language

## Code Standards

- Bash scripts must use `set -euo pipefail`
- Keep scripts focused — thin wrappers, not application logic
- No external dependencies beyond `jq` for core functionality
- Test any new script with the existing test harness

## Reporting Bugs

Open an issue with:
- What you expected
- What happened
- Steps to reproduce
- Output of `bash scripts/detect.sh .`

## Scope

Matra is deliberately minimal. Proposals that add runtime dependencies, require
compilation, or significantly increase complexity may be declined. When in
doubt, open an issue to discuss before writing code.
