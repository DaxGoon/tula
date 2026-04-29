# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in Matra, please report it responsibly.

**Do not open a public issue.**

Instead, email the maintainer directly at the address listed in the git log,
with:

- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

You should receive an acknowledgement within 48 hours. A fix will be prioritised
based on severity.

## Scope

Matra is a static analysis tool that reads source files and runs external
linters. Security concerns include:

- **Rule injection** — malicious YAML rules that execute code
- **Path traversal** — scan scripts accessing files outside the project root
- **Output injection** — findings that could inject content into reports

## Supported Versions

Only the latest version on `main` receives security updates. Pin to a specific
commit if you need stability.
