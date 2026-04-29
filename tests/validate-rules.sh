#!/usr/bin/env bash
set -euo pipefail

MATRA_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RULES_DIR="$MATRA_ROOT/rules"
PASS=0
FAIL=0
TOTAL=0

validate_yaml() {
  local file="$1"
  TOTAL=$((TOTAL + 1))

  if command -v python3 &>/dev/null; then
    if python3 -c "import yaml; yaml.safe_load(open('$file'))" 2>/dev/null; then
      PASS=$((PASS + 1))
    else
      echo "FAIL: $file — YAML parse error"
      FAIL=$((FAIL + 1))
    fi
  elif command -v ruby &>/dev/null; then
    if ruby -ryaml -e "YAML.safe_load(File.read('$file'))" 2>/dev/null; then
      PASS=$((PASS + 1))
    else
      echo "FAIL: $file — YAML parse error"
      FAIL=$((FAIL + 1))
    fi
  else
    echo "SKIP: $file — no YAML parser available (need python3 or ruby)"
    return
  fi
}

validate_rule_fields() {
  local file="$1"

  if ! command -v python3 &>/dev/null; then
    return
  fi

  python3 -c "
import yaml, sys

with open('$file') as f:
    data = yaml.safe_load(f)

if data is None:
    print(f'WARN: $file — empty file')
    sys.exit(0)

valid_categories = {'security', 'reliability', 'performance', 'maintainability', 'documentation'}
valid_severities = {'critical', 'high', 'medium', 'low'}

errors = []

# Check tools section
for tool in data.get('tools', []):
    if 'id' not in tool:
        errors.append('tool missing id')
    if 'invocation' not in tool:
        errors.append(f'tool {tool.get(\"id\", \"?\")} missing invocation')

# Check patterns section
for pattern in data.get('patterns', []):
    if 'id' not in pattern:
        errors.append('pattern missing id')
    sev = pattern.get('severity', '')
    if sev and sev not in valid_severities:
        errors.append(f'pattern {pattern.get(\"id\", \"?\")} invalid severity: {sev}')
    cat = pattern.get('category', '')
    if cat and cat not in valid_categories:
        errors.append(f'pattern {pattern.get(\"id\", \"?\")} invalid category: {cat}')

# Check thresholds section
for threshold in data.get('thresholds', []):
    if 'id' not in threshold:
        errors.append('threshold missing id')
    if 'value' not in threshold:
        errors.append(f'threshold {threshold.get(\"id\", \"?\")} missing value')
    sev = threshold.get('severity', '')
    if sev and sev not in valid_severities:
        errors.append(f'threshold {threshold.get(\"id\", \"?\")} invalid severity: {sev}')

# Check semantic section
for sem in data.get('semantic', []):
    if 'id' not in sem:
        errors.append('semantic rule missing id')
    if 'guidance' not in sem:
        errors.append(f'semantic {sem.get(\"id\", \"?\")} missing guidance')

if errors:
    for e in errors:
        print(f'WARN: $file — {e}')
" 2>/dev/null || true
}

echo "Validating rule files..."
echo

# Validate all YAML files
while IFS= read -r file; do
  validate_yaml "$file"
  validate_rule_fields "$file"
done < <(find "$RULES_DIR" -name "*.yml" -type f | sort)

echo
echo "Results: $PASS passed, $FAIL failed out of $TOTAL files"

if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
echo "All rule files valid."
