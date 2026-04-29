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

# --- golangci-lint ---
if command -v golangci-lint &>/dev/null; then
  GCL_VERSION=$(golangci-lint version --format short 2>/dev/null || echo "unknown")
  START=$(date +%s.%N)
  GCL_OUTPUT=""
  GCL_EXIT=0
  GCL_OUTPUT=$(cd "$PROJECT_ROOT" && golangci-lint run --out-format json ./... 2>/dev/null) || GCL_EXIT=$?

  FINDINGS="[]"
  if [[ -n "$GCL_OUTPUT" ]]; then
    FINDINGS=$(echo "$GCL_OUTPUT" | jq '[
      .Issues // [] | .[] | {
        message: .Text,
        severity_raw: (.Severity // "warning"),
        line: .Pos.Line,
        file: .Pos.Filename,
        rule: .FromLinter
      }
    ]' 2>/dev/null || echo "[]")
  fi

  END=$(date +%s.%N)
  RUNTIME=$(echo "$END - $START" | bc 2>/dev/null || echo "0")
  add_result "golangci-lint" "$GCL_VERSION" "$FINDINGS" "$GCL_EXIT" "$RUNTIME"
else
  echo "Warning: golangci-lint not found, skipping" >&2
fi

# --- go vet ---
if command -v go &>/dev/null; then
  GO_VERSION=$(go version 2>/dev/null | awk '{print $3}' | tr -d 'go' || echo "unknown")
  START=$(date +%s.%N)
  VET_OUTPUT=""
  VET_EXIT=0
  VET_OUTPUT=$(cd "$PROJECT_ROOT" && go vet ./... 2>&1) || VET_EXIT=$?

  FINDINGS="[]"
  if [[ -n "$VET_OUTPUT" ]]; then
    FINDINGS=$(echo "$VET_OUTPUT" | while IFS= read -r line; do
      if [[ "$line" =~ ^([^:]+):([0-9]+):[0-9]*:?[[:space:]]*(.+)$ ]]; then
        FILE="${BASH_REMATCH[1]}"
        LINE="${BASH_REMATCH[2]}"
        MSG="${BASH_REMATCH[3]}"
        jq -n --arg m "$MSG" --arg s "error" --argjson l "$LINE" --arg f "$FILE" --arg r "go-vet" \
          '{message:$m,severity_raw:$s,line:$l,file:$f,rule:$r}'
      fi
    done | jq -s '.' 2>/dev/null || echo "[]")
  fi

  END=$(date +%s.%N)
  RUNTIME=$(echo "$END - $START" | bc 2>/dev/null || echo "0")
  add_result "go-vet" "$GO_VERSION" "$FINDINGS" "$VET_EXIT" "$RUNTIME"
else
  echo "Warning: go not found, skipping vet" >&2
fi

# --- govulncheck ---
if command -v govulncheck &>/dev/null; then
  GOVULN_VERSION=$(govulncheck -version 2>/dev/null | head -1 || echo "unknown")
  START=$(date +%s.%N)
  GOVULN_OUTPUT=""
  GOVULN_EXIT=0
  GOVULN_OUTPUT=$(cd "$PROJECT_ROOT" && govulncheck -json ./... 2>/dev/null) || GOVULN_EXIT=$?

  FINDINGS="[]"
  if [[ -n "$GOVULN_OUTPUT" ]]; then
    FINDINGS=$(echo "$GOVULN_OUTPUT" | jq -s '[
      .[] | select(.osv != null) | {
        message: .osv.summary,
        severity_raw: (.osv.database_specific.severity // "medium"),
        line: 0,
        file: (.osv.affected[0].package.name // "unknown"),
        rule: .osv.id
      }
    ]' 2>/dev/null || echo "[]")
  fi

  END=$(date +%s.%N)
  RUNTIME=$(echo "$END - $START" | bc 2>/dev/null || echo "0")
  add_result "govulncheck" "$GOVULN_VERSION" "$FINDINGS" "$GOVULN_EXIT" "$RUNTIME"
else
  echo "Warning: govulncheck not found, skipping" >&2
fi

# --- staticcheck ---
if command -v staticcheck &>/dev/null; then
  SC_VERSION=$(staticcheck -version 2>/dev/null | awk '{print $NF}' || echo "unknown")
  START=$(date +%s.%N)
  SC_OUTPUT=""
  SC_EXIT=0
  SC_OUTPUT=$(cd "$PROJECT_ROOT" && staticcheck -f json ./... 2>/dev/null) || SC_EXIT=$?

  FINDINGS="[]"
  if [[ -n "$SC_OUTPUT" ]]; then
    FINDINGS=$(echo "$SC_OUTPUT" | jq -s '[
      .[] | {
        message: .message,
        severity_raw: (.severity // "warning"),
        line: .location.line,
        file: .location.file,
        rule: .code
      }
    ]' 2>/dev/null || echo "[]")
  fi

  END=$(date +%s.%N)
  RUNTIME=$(echo "$END - $START" | bc 2>/dev/null || echo "0")
  add_result "staticcheck" "$SC_VERSION" "$FINDINGS" "$SC_EXIT" "$RUNTIME"
else
  echo "Warning: staticcheck not found, skipping" >&2
fi

echo "$RESULTS" | jq '.'
