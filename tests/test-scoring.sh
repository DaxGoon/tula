#!/usr/bin/env bash
set -euo pipefail

MATRA_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

assert_score_range() {
  local name="$1" score="$2" min="$3" max="$4"
  if [[ "$score" -ge "$min" && "$score" -le "$max" ]]; then
    echo "  PASS: $name — score $score in range [$min, $max]"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $name — score $score not in range [$min, $max]"
    FAIL=$((FAIL + 1))
  fi
}

assert_exit_code() {
  local name="$1" actual="$2" expected="$3"
  if [[ "$actual" -eq "$expected" ]]; then
    echo "  PASS: $name — exit code $actual"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $name — exit code $actual (expected $expected)"
    FAIL=$((FAIL + 1))
  fi
}

echo "Testing scoring with known fixtures..."
echo

# Test 1: Fixtures directory should have issues and score below 1000
echo "Test 1: Fixtures with known issues"
exit_code=0
output=$("$MATRA_ROOT/scripts/ci.sh" \
  --project-root "$MATRA_ROOT/tests/fixtures" \
  --format json \
  --deterministic \
  --threshold 800 2>/dev/null) || exit_code=$?

score=$(echo "$output" | jq '.score // 0')
total_issues=$(echo "$output" | jq '.issues.total // 0')

assert_score_range "fixtures score" "$score" 0 999
if [[ "$total_issues" -gt 0 ]]; then
  echo "  PASS: fixtures have issues ($total_issues found)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: expected issues in fixtures, found 0"
  FAIL=$((FAIL + 1))
fi

# Test 2: High threshold should fail
echo
echo "Test 2: High threshold causes failure"
exit_code=0
"$MATRA_ROOT/scripts/ci.sh" \
  --project-root "$MATRA_ROOT/tests/fixtures" \
  --format json \
  --deterministic \
  --threshold 999 >/dev/null 2>&1 || exit_code=$?

assert_exit_code "high threshold" "$exit_code" 2

# Test 3: Low threshold should pass
echo
echo "Test 3: Low threshold causes pass"
exit_code=0
"$MATRA_ROOT/scripts/ci.sh" \
  --project-root "$MATRA_ROOT/tests/fixtures" \
  --format json \
  --deterministic \
  --threshold 0 >/dev/null 2>&1 || exit_code=$?

# Exit code 0 (pass) or 1 (warn) are both acceptable
if [[ "$exit_code" -le 1 ]]; then
  echo "  PASS: low threshold — exit code $exit_code (pass/warn)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: low threshold — exit code $exit_code (expected 0 or 1)"
  FAIL=$((FAIL + 1))
fi

# Test 4: Text format output
echo
echo "Test 4: Text format output"
text_out=$("$MATRA_ROOT/scripts/ci.sh" \
  --project-root "$MATRA_ROOT/tests/fixtures" \
  --format text \
  --deterministic \
  --threshold 0 2>/dev/null) || true

if echo "$text_out" | grep -q "Matra:"; then
  echo "  PASS: text output contains score header"
  PASS=$((PASS + 1))
else
  echo "  FAIL: text output missing score header"
  FAIL=$((FAIL + 1))
fi

# Test 5: JSON report structure
echo
echo "Test 5: JSON report has required fields"
required_fields=("score" "profile" "threshold" "result" "issues" "tools" "findings")
for field in "${required_fields[@]}"; do
  if echo "$output" | jq -e ".$field" &>/dev/null; then
    echo "  PASS: JSON has field '$field'"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: JSON missing field '$field'"
    FAIL=$((FAIL + 1))
  fi
done

echo
echo "Results: $PASS passed, $FAIL failed"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
echo "All scoring tests passed."
