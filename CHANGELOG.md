# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.1.0] - 2026-04-25

### Added

- Initial release
- YAML-based rule engine across 5 categories (security, reliability, performance, maintainability, documentation)
- Support for Python, JavaScript/TypeScript, Java, Go, C/C++
- Scoring system on a 1000-point scale with configurable profiles
- CI/CD script with deterministic scoring mode
- Adapters for Claude Code, GitHub Copilot, and Cursor
- Project-level rule overrides and custom rules
- Auto-detection of installed linters with graceful degradation
