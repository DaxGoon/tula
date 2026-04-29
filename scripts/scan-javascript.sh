#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=""
FILES=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-root) PROJECT_ROOT="$2"; shift 2 ;;
    --files) shift; while [[ $# -gt 0 && ! "$1" =~ ^-- ]]; do FILES+=("$1"); shift; done ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$PROJECT_ROOT" ]]; then
  echo "Error: --project-root is required" >&2
  exit 1
fi

PROJECT_ROOT=$(cd "$PROJECT_ROOT" && pwd)
RESULTS="[]"

add_result() {
  local tool="$1" version="$2" findings="$3" exit_code="$4" runtime="$5"
  RESULTS=$(echo "$RESULTS" | jq --arg t "$tool" --arg v "$version" \
    --argjson f "$findings" --argjson ec "$exit_code" --arg rt "$runtime" \
    '. + [{"tool":$t,"version":$v,"findings":$f,"exit_code":$ec,"runtime_seconds":($rt|tonumber)}]')
}

get_file_args() {
  if [[ ${#FILES[@]} -gt 0 ]]; then
    printf '%s ' "${FILES[@]}"
  else
    echo "$PROJECT_ROOT"
  fi
}

# --- ESLint ---
if command -v eslint &>/dev/null; then
  ESLINT_VERSION=$(eslint --version 2>/dev/null | tr -d 'v' || echo "unknown")
  START=$(date +%s.%N)
  ESLINT_OUTPUT=""
  ESLINT_EXIT=0
  ESLINT_OUTPUT=$(eslint -f json --no-error-on-unmatched-pattern $(get_file_args) 2>/dev/null) || ESLINT_EXIT=$?

  FINDINGS="[]"
  if [[ -n "$ESLINT_OUTPUT" && "$ESLINT_OUTPUT" != "[]" ]]; then
    FINDINGS=$(echo "$ESLINT_OUTPUT" | jq '[
      .[] | .filePath as $file | .messages[] | {
        message: .message,
        severity_raw: (if .severity == 2 then "error" elif .severity == 1 then "warning" else "info" end),
        line: (.line // 0),
        file: $file,
        rule: (.ruleId // "unknown")
      }
    ]' 2>/dev/null || echo "[]")
  fi

  END=$(date +%s.%N)
  RUNTIME=$(echo "$END - $START" | bc 2>/dev/null || echo "0")
  add_result "eslint" "$ESLINT_VERSION" "$FINDINGS" "$ESLINT_EXIT" "$RUNTIME"
else
  echo "Warning: eslint not found, skipping" >&2
fi

# --- TypeScript Compiler ---
if command -v tsc &>/dev/null && [[ -f "$PROJECT_ROOT/tsconfig.json" ]]; then
  TSC_VERSION=$(tsc --version 2>/dev/null | awk '{print $NF}' || echo "unknown")
  START=$(date +%s.%N)
  TSC_OUTPUT=""
  TSC_EXIT=0
  TSC_OUTPUT=$(tsc --noEmit --pretty false --project "$PROJECT_ROOT/tsconfig.json" 2>&1) || TSC_EXIT=$?

  FINDINGS="[]"
  if [[ -n "$TSC_OUTPUT" ]]; then
    FINDINGS=$(echo "$TSC_OUTPUT" | while IFS= read -r line; do
      if [[ "$line" =~ ^(.+)\(([0-9]+),[0-9]+\):\ (error|warning)\ (TS[0-9]+):\ (.+)$ ]]; then
        FILE="${BASH_REMATCH[1]}"
        LINE="${BASH_REMATCH[2]}"
        SEV="${BASH_REMATCH[3]}"
        RULE="${BASH_REMATCH[4]}"
        MSG="${BASH_REMATCH[5]}"
        jq -n --arg m "$MSG" --arg s "$SEV" --argjson l "$LINE" --arg f "$FILE" --arg r "$RULE" \
          '{message:$m,severity_raw:$s,line:$l,file:$f,rule:$r}'
      fi
    done | jq -s '.' 2>/dev/null || echo "[]")
  fi

  END=$(date +%s.%N)
  RUNTIME=$(echo "$END - $START" | bc 2>/dev/null || echo "0")
  add_result "tsc" "$TSC_VERSION" "$FINDINGS" "$TSC_EXIT" "$RUNTIME"
elif ! command -v tsc &>/dev/null; then
  echo "Warning: tsc not found, skipping" >&2
fi

# --- npm audit ---
if command -v npm &>/dev/null && [[ -f "$PROJECT_ROOT/package-lock.json" || -f "$PROJECT_ROOT/package.json" ]]; then
  NPM_VERSION=$(npm --version 2>/dev/null || echo "unknown")
  START=$(date +%s.%N)
  AUDIT_OUTPUT=""
  AUDIT_EXIT=0
  AUDIT_OUTPUT=$(cd "$PROJECT_ROOT" && npm audit --json 2>/dev/null) || AUDIT_EXIT=$?

  FINDINGS="[]"
  if [[ -n "$AUDIT_OUTPUT" ]]; then
    FINDINGS=$(echo "$AUDIT_OUTPUT" | jq '[
      .vulnerabilities // {} | to_entries[] | .value | {
        message: .title,
        severity_raw: .severity,
        line: 0,
        file: (.name // "package.json"),
        rule: (.via[0].url // .via[0] // "unknown" | tostring)
      }
    ]' 2>/dev/null || echo "[]")
  fi

  END=$(date +%s.%N)
  RUNTIME=$(echo "$END - $START" | bc 2>/dev/null || echo "0")
  add_result "npm-audit" "$NPM_VERSION" "$FINDINGS" "$AUDIT_EXIT" "$RUNTIME"
elif ! command -v npm &>/dev/null; then
  echo "Warning: npm not found, skipping audit" >&2
fi

# --- Semgrep ---
if command -v semgrep &>/dev/null; then
  SEMGREP_VERSION=$(semgrep --version 2>/dev/null || echo "unknown")
  START=$(date +%s.%N)
  SEMGREP_OUTPUT=""
  SEMGREP_EXIT=0

  FILE_ARGS=""
  if [[ ${#FILES[@]} -gt 0 ]]; then
    for f in "${FILES[@]}"; do FILE_ARGS+=" --include $f"; done
  fi

  SEMGREP_OUTPUT=$(semgrep scan --config auto --lang js --lang ts --json \
    $FILE_ARGS "$PROJECT_ROOT" 2>/dev/null) || SEMGREP_EXIT=$?

  FINDINGS="[]"
  if [[ -n "$SEMGREP_OUTPUT" ]]; then
    FINDINGS=$(echo "$SEMGREP_OUTPUT" | jq '[
      .results // [] | .[] | {
        message: .extra.message,
        severity_raw: .extra.severity,
        line: .start.line,
        file: .path,
        rule: .check_id
      }
    ]' 2>/dev/null || echo "[]")
  fi

  END=$(date +%s.%N)
  RUNTIME=$(echo "$END - $START" | bc 2>/dev/null || echo "0")
  add_result "semgrep" "$SEMGREP_VERSION" "$FINDINGS" "$SEMGREP_EXIT" "$RUNTIME"
else
  echo "Warning: semgrep not found, skipping" >&2
fi

echo "$RESULTS" | jq '.'
