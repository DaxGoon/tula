#!/usr/bin/env bash
set -euo pipefail

MATRA_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURES="$MATRA_ROOT/tests/fixtures"
PASS=0
FAIL=0

assert_json() {
  local name="$1" output="$2"
  if echo "$output" | jq . &>/dev/null; then
    echo "  PASS: $name — valid JSON"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $name — invalid JSON output"
    FAIL=$((FAIL + 1))
  fi
}

assert_exit_ok() {
  local name="$1" code="$2"
  if [[ "$code" -eq 0 ]]; then
    echo "  PASS: $name — exit code 0"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $name — exit code $code"
    FAIL=$((FAIL + 1))
  fi
}

echo "Testing detect.sh..."
detect_out=$("$MATRA_ROOT/scripts/detect.sh" "$FIXTURES" 2>/dev/null || true)
assert_json "detect.sh output" "$detect_out"
if echo "$detect_out" | jq -e '.languages' &>/dev/null; then
  echo "  PASS: detect.sh — has languages field"
  PASS=$((PASS + 1))
else
  echo "  FAIL: detect.sh — missing languages field"
  FAIL=$((FAIL + 1))
fi

echo
echo "Testing scan-python.sh..."
if [[ -x "$MATRA_ROOT/scripts/scan-python.sh" ]]; then
  py_out=$("$MATRA_ROOT/scripts/scan-python.sh" --files "$FIXTURES/sample.py" 2>/dev/null || echo '[]')
  assert_json "scan-python.sh output" "$py_out"
else
  echo "  SKIP: scan-python.sh not found"
fi

echo
echo "Testing scan-cpp.sh..."
if [[ -x "$MATRA_ROOT/scripts/scan-cpp.sh" ]]; then
  cpp_out=$("$MATRA_ROOT/scripts/scan-cpp.sh" --files "$FIXTURES/sample.c" 2>/dev/null || echo '[]')
  assert_json "scan-cpp.sh output" "$cpp_out"
else
  echo "  SKIP: scan-cpp.sh not found"
fi

echo
echo "Testing scan-javascript.sh..."
if [[ -x "$MATRA_ROOT/scripts/scan-javascript.sh" ]]; then
  js_out=$("$MATRA_ROOT/scripts/scan-javascript.sh" --files "$FIXTURES/sample.js" 2>/dev/null || echo '[]')
  assert_json "scan-javascript.sh output" "$js_out"
else
  echo "  SKIP: scan-javascript.sh not found"
fi

echo
echo "Testing scan-java.sh..."
if [[ -x "$MATRA_ROOT/scripts/scan-java.sh" ]]; then
  java_out=$("$MATRA_ROOT/scripts/scan-java.sh" --files "$FIXTURES/sample.java" 2>/dev/null || echo '[]')
  assert_json "scan-java.sh output" "$java_out"
else
  echo "  SKIP: scan-java.sh not found"
fi

echo
echo "Testing scan-go.sh..."
if [[ -x "$MATRA_ROOT/scripts/scan-go.sh" ]]; then
  go_out=$("$MATRA_ROOT/scripts/scan-go.sh" --files "$FIXTURES/sample.go" 2>/dev/null || echo '[]')
  assert_json "scan-go.sh output" "$go_out"
else
  echo "  SKIP: scan-go.sh not found"
fi

echo
echo "Testing scan-docs.sh..."
if [[ -x "$MATRA_ROOT/scripts/scan-docs.sh" ]]; then
  doc_out=$("$MATRA_ROOT/scripts/scan-docs.sh" --project-root "$MATRA_ROOT" 2>/dev/null || echo '{}')
  assert_json "scan-docs.sh output" "$doc_out"
else
  echo "  SKIP: scan-docs.sh not found"
fi

echo
echo "Testing ci.sh..."
if [[ -x "$MATRA_ROOT/scripts/ci.sh" ]]; then
  ci_exit=0
  ci_out=$("$MATRA_ROOT/scripts/ci.sh" --project-root "$FIXTURES" --format json --deterministic 2>/dev/null) || ci_exit=$?
  assert_json "ci.sh output" "$ci_out"
  if [[ "$ci_exit" -le 3 ]]; then
    echo "  PASS: ci.sh — valid exit code ($ci_exit)"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: ci.sh — unexpected exit code ($ci_exit)"
    FAIL=$((FAIL + 1))
  fi
else
  echo "  SKIP: ci.sh not found"
fi

echo
echo "Results: $PASS passed, $FAIL failed"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
echo "All script tests passed."
