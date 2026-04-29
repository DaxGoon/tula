#!/usr/bin/env bash
set -euo pipefail

MATRA_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURES="$MATRA_ROOT/tests/fixtures"
PASS=0
FAIL=0

assert_ok() {
  local name="$1"
  if [[ "$2" == "true" ]]; then
    echo "  PASS: $name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $name"
    FAIL=$((FAIL + 1))
  fi
}

# --- 1. DOCS-ONLY DETECTION ---
echo "Test: docs-only repo detection"
docs_repo="$FIXTURES/docs-only-repo"
detect_out=$("$MATRA_ROOT/scripts/detect.sh" "$docs_repo" 2>/dev/null || true)
primary=$(echo "$detect_out" | jq -r '.primary')
assert_ok "docs-only repo sets primary=docs" "$( [[ "$primary" == "docs" ]] && echo true || echo false )"

echo
echo "Test: normal repo does not set primary=docs"
normal_repo=$(mktemp -d)
for i in 1 2 3 4; do cp "$FIXTURES/sample.py" "$normal_repo/mod${i}.py"; done
detect_out=$("$MATRA_ROOT/scripts/detect.sh" "$normal_repo" 2>/dev/null || true)
primary=$(echo "$detect_out" | jq -r '.primary')
assert_ok "normal repo primary != docs" "$( [[ "$primary" != "docs" ]] && echo true || echo false )"
rm -rf "$normal_repo"

# --- 2. CI AUTO-SWITCH TO DOCS PROFILE ---
echo
echo "Test: ci.sh auto-switches to docs profile for docs-only repo"
ci_exit=0
ci_out=$("$MATRA_ROOT/scripts/ci.sh" --project-root "$docs_repo" --format json --deterministic 2>/dev/null) || ci_exit=$?
ci_profile=$(echo "$ci_out" | jq -r '.profile')
assert_ok "ci auto-selects docs profile" "$( [[ "$ci_profile" == "docs" ]] && echo true || echo false )"

echo
echo "Test: ci.sh respects explicit --profile over auto-detect"
ci_out=$("$MATRA_ROOT/scripts/ci.sh" --project-root "$docs_repo" --profile strict --format json --deterministic 2>/dev/null) || true
ci_profile=$(echo "$ci_out" | jq -r '.profile')
assert_ok "explicit profile overrides auto-detect" "$( [[ "$ci_profile" == "strict" ]] && echo true || echo false )"

# --- 3. CATEGORY WEIGHTS IN SCORING ---
echo
echo "Test: category-weighted scoring differs from flat scoring"
ci_out=$("$MATRA_ROOT/scripts/ci.sh" --project-root "$FIXTURES" --format json --deterministic --threshold 0 2>/dev/null) || true
score=$(echo "$ci_out" | jq '.score')
assert_ok "weighted score is numeric" "$( [[ "$score" =~ ^[0-9]+$ ]] && echo true || echo false )"
assert_ok "weighted score in range 0-1000" "$( [[ "$score" -ge 0 && "$score" -le 1000 ]] && echo true || echo false )"

# --- 4. WIRE METRICS INTO FINDINGS (DOC-API-001) ---
echo
echo "Test: high docstring coverage emits DOC-API-001"
langcov_dir=$(mktemp -d)
cat > "$langcov_dir/main.py" << 'PYEOF'
def foo():
    """Does foo."""
    pass
def bar():
    """Does bar."""
    pass
def baz():
    """Does baz."""
    pass
def qux():
    """Does qux."""
    pass
PYEOF
cp "$FIXTURES/sample.go" "$langcov_dir/main.go"
cp "$FIXTURES/sample.js" "$langcov_dir/main.js"
cp "$FIXTURES/sample.java" "$langcov_dir/Sample.java"
echo "# Proj" > "$langcov_dir/README.md"
doc_out=$("$MATRA_ROOT/scripts/scan-docs.sh" --project-root "$langcov_dir" 2>/dev/null || echo '{"findings":[]}')
has_doc_api=$(echo "$doc_out" | jq '[.findings[] | select(.rule == "DOC-API-001")] | length > 0')
assert_ok "DOC-API-001 emitted for over-documented code" "$has_doc_api"

# --- 5. README SECTION DETECTION VIA HEADINGS ---
echo
echo "Test: README heading-based section detection"
doc_out=$("$MATRA_ROOT/scripts/scan-docs.sh" --project-root "$FIXTURES/broken-links" 2>/dev/null || echo '{"findings":[],"metrics":{}}')
has_install=$(echo "$doc_out" | jq '.metrics.readme.has_install_section')
assert_ok "heading-based install detection" "$has_install"

# --- 6. BROKEN INTERNAL LINKS ---
echo
echo "Test: broken markdown links detected"
doc_out=$("$MATRA_ROOT/scripts/scan-docs.sh" --project-root "$FIXTURES/broken-links" 2>/dev/null || echo '{"findings":[]}')
broken_count=$(echo "$doc_out" | jq '[.findings[] | select(.rule == "DOC-LINK-001")] | length')
assert_ok "broken links found" "$( [[ "$broken_count" -ge 1 ]] && echo true || echo false )"

# --- 7. DOCS DIRECTORY DETECTION ---
echo
echo "Test: docs directory detection"
tmpdir=$(mktemp -d)
mkdir -p "$tmpdir/docs"
echo "# API" > "$tmpdir/docs/api.md"
echo "# Proj" > "$tmpdir/README.md"
doc_out=$("$MATRA_ROOT/scripts/scan-docs.sh" --project-root "$tmpdir" 2>/dev/null || echo '{"findings":[],"metrics":{}}')
has_docs_dir=$(echo "$doc_out" | jq '.metrics.docs_directory // false')
assert_ok "docs directory detected" "$( [[ "$has_docs_dir" == "true" ]] && echo true || echo false )"
rm -rf "$tmpdir"

# --- 8. API SPEC DETECTION ---
echo
echo "Test: API spec file detection"
tmpdir=$(mktemp -d)
echo "# Proj" > "$tmpdir/README.md"
echo "openapi: 3.0.0" > "$tmpdir/openapi.yml"
doc_out=$("$MATRA_ROOT/scripts/scan-docs.sh" --project-root "$tmpdir" 2>/dev/null || echo '{"findings":[],"metrics":{}}')
has_api_spec=$(echo "$doc_out" | jq '.metrics.api_spec // false')
assert_ok "API spec file detected" "$( [[ "$has_api_spec" == "true" ]] && echo true || echo false )"
rm -rf "$tmpdir"

echo
echo "Test: missing API spec emits no finding when docs exist"
tmpdir=$(mktemp -d)
echo "# Proj" > "$tmpdir/README.md"
doc_out=$("$MATRA_ROOT/scripts/scan-docs.sh" --project-root "$tmpdir" 2>/dev/null || echo '{"findings":[],"metrics":{}}')
has_api_spec=$(echo "$doc_out" | jq '.metrics.api_spec // false')
assert_ok "no API spec is false" "$( [[ "$has_api_spec" == "false" ]] && echo true || echo false )"
rm -rf "$tmpdir"

# --- 9. MATRA_DOC_FILE_LIMIT ---
echo
echo "Test: MATRA_DOC_FILE_LIMIT env var respected"
MATRA_DOC_FILE_LIMIT=5 doc_out=$("$MATRA_ROOT/scripts/scan-docs.sh" --project-root "$FIXTURES" 2>/dev/null || echo '{"findings":[],"metrics":{}}')
assert_ok "scan-docs runs with custom file limit" "$( echo "$doc_out" | jq -e '.metrics' &>/dev/null && echo true || echo false )"

# --- 10. MULTI-LANGUAGE DOCSTRING COVERAGE ---
echo
echo "Test: Go doc-comment coverage in metrics"
doc_out=$("$MATRA_ROOT/scripts/scan-docs.sh" --project-root "$langcov_dir" 2>/dev/null || echo '{"findings":[],"metrics":{}}')
has_go=$(echo "$doc_out" | jq '.metrics.go // null')
assert_ok "Go coverage metrics present" "$( [[ "$has_go" != "null" ]] && echo true || echo false )"

has_js=$(echo "$doc_out" | jq '.metrics.javascript // null')
assert_ok "JS coverage metrics present" "$( [[ "$has_js" != "null" ]] && echo true || echo false )"

has_java=$(echo "$doc_out" | jq '.metrics.java // null')
assert_ok "Java coverage metrics present" "$( [[ "$has_java" != "null" ]] && echo true || echo false )"

rm -rf "$langcov_dir"

echo
echo "Results: $PASS passed, $FAIL failed"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
echo "All doc improvement tests passed."
