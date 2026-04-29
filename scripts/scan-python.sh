#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=""
FILES=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-root)
      PROJECT_ROOT="$2"
      shift 2
      ;;
    --files)
      shift
      while [[ $# -gt 0 && ! "$1" =~ ^-- ]]; do
        FILES+=("$1")
        shift
      done
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$PROJECT_ROOT" ]]; then
  PROJECT_ROOT="$(pwd)"
fi
PROJECT_ROOT=$(cd "$PROJECT_ROOT" && pwd)

if [[ ${#FILES[@]} -eq 0 ]]; then
  while IFS= read -r -d '' f; do
    FILES+=("$f")
  done < <(find "$PROJECT_ROOT" -name '*.py' \
    -not -path '*/.git/*' \
    -not -path '*/.venv/*' \
    -not -path '*/venv/*' \
    -not -path '*/__pycache__/*' \
    -not -path '*/node_modules/*' \
    -not -path '*/build/*' \
    -not -path '*/dist/*' \
    -print0 2>/dev/null)
fi

if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "[]"
  exit 0
fi

RESULTS=()

get_version() {
  local tool="$1"
  case "$tool" in
    bandit)  bandit --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' || echo "unknown" ;;
    pylint)  pylint --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' || echo "unknown" ;;
    flake8)  flake8 --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1 || echo "unknown" ;;
    mypy)    mypy --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' || echo "unknown" ;;
    safety)  safety --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' || echo "unknown" ;;
    *)       echo "unknown" ;;
  esac
}

run_tool() {
  local tool="$1"
  shift
  local files_arg=("$@")
  local start_time exit_code output version

  start_time=$(date +%s.%N 2>/dev/null || python3 -c 'import time; print(time.time())')
  version=$(get_version "$tool")

  case "$tool" in
    bandit)
      output=$(bandit -f json -q "${files_arg[@]}" 2>/dev/null) || true
      exit_code=$?
      local findings="[]"
      if [[ -n "$output" ]]; then
        findings=$(echo "$output" | python3 -c "
import sys, json
data = json.load(sys.stdin)
sev_map = {'HIGH': 'high', 'MEDIUM': 'medium', 'LOW': 'low'}
out = []
for r in data.get('results', []):
    out.append({
        'message': r.get('issue_text', 'Security issue'),
        'severity': sev_map.get(r.get('issue_severity', ''), 'low'),
        'category': 'security',
        'line': r.get('line_number'),
        'file': r.get('filename', ''),
        'rule': r.get('test_name', ''),
        'confidence': r.get('issue_confidence', '')
    })
json.dump(out, sys.stdout)
" 2>/dev/null) || findings="[]"
      fi
      ;;

    pylint)
      output=$(pylint --output-format=json --disable=C0114,C0115,C0116 "${files_arg[@]}" 2>/dev/null) || true
      exit_code=$?
      local findings="[]"
      if [[ -n "$output" ]]; then
        findings=$(echo "$output" | python3 -c "
import sys, json
data = json.load(sys.stdin)
sev_map = {'error': 'high', 'warning': 'medium', 'refactor': 'low', 'convention': 'low', 'info': 'low'}
out = []
for r in data:
    mid = r.get('message-id', '')
    if mid.startswith(('W1', 'E1')):
        cat = 'security'
    elif mid.startswith(('E0', 'F')):
        cat = 'reliability'
    elif mid in ('W0622', 'R1729', 'C0200'):
        cat = 'performance'
    else:
        cat = 'maintainability'
    out.append({
        'message': r.get('message', ''),
        'severity': sev_map.get(r.get('type', ''), 'low'),
        'category': cat,
        'line': r.get('line'),
        'column': r.get('column'),
        'file': r.get('path', ''),
        'rule': mid
    })
json.dump(out, sys.stdout)
" 2>/dev/null) || findings="[]"
      fi
      ;;

    flake8)
      output=$(flake8 --max-line-length=88 --ignore=E203,W503 --format='%(path)s:%(row)d:%(col)d: %(code)s %(text)s' "${files_arg[@]}" 2>/dev/null) || true
      exit_code=$?
      local findings="[]"
      if [[ -n "$output" ]]; then
        findings=$(echo "$output" | python3 -c "
import sys, json, re
out = []
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    m = re.match(r'(.+):(\d+):(\d+): ([A-Z]\d+) (.+)', line)
    if m:
        f, ln, col, code, msg = m.groups()
        if code.startswith('E9'):
            sev = 'high'
        elif code.startswith('E7'):
            sev = 'medium'
        elif code.startswith('W'):
            sev = 'low'
        else:
            sev = 'low'
        out.append({
            'message': msg,
            'severity': sev,
            'category': 'maintainability',
            'line': int(ln),
            'column': int(col),
            'file': f,
            'rule': code
        })
json.dump(out, sys.stdout)
" 2>/dev/null) || findings="[]"
      fi
      ;;

    mypy)
      output=$(mypy --show-error-codes "${files_arg[@]}" 2>/dev/null) || true
      exit_code=$?
      local findings="[]"
      if [[ -n "$output" ]]; then
        findings=$(echo "$output" | python3 -c "
import sys, json, re
sev_map = {'error': 'medium', 'warning': 'low', 'note': 'low'}
out = []
for line in sys.stdin:
    line = line.strip()
    m = re.match(r'(.+):(\d+): ([^:]+): (.+)', line)
    if m:
        f, ln, sev, msg = m.groups()
        error_code = ''
        code_match = re.search(r'\[([^\]]+)\]$', msg)
        if code_match:
            error_code = code_match.group(1)
        out.append({
            'message': msg,
            'severity': sev_map.get(sev.strip().lower(), 'low'),
            'category': 'reliability',
            'line': int(ln),
            'file': f,
            'rule': error_code or 'mypy'
        })
json.dump(out, sys.stdout)
" 2>/dev/null) || findings="[]"
      fi
      ;;

    safety)
      local req_file=""
      for candidate in "$PROJECT_ROOT/requirements.txt" "$PROJECT_ROOT/requirements/base.txt"; do
        if [[ -f "$candidate" ]]; then
          req_file="$candidate"
          break
        fi
      done
      if [[ -z "$req_file" ]]; then
        echo '{"tool":"safety","version":"'"$version"'","findings":[],"exit_code":0,"runtime_seconds":0.0,"skipped":"no requirements.txt found"}'
        return
      fi
      output=$(safety check --json --file "$req_file" 2>/dev/null) || true
      exit_code=$?
      local findings="[]"
      if [[ -n "$output" ]]; then
        findings=$(echo "$output" | python3 -c "
import sys, json
data = json.load(sys.stdin)
out = []
if isinstance(data, list):
    for v in data:
        pkg = v[0] if isinstance(v, list) else v.get('package', 'unknown')
        ver = v[2] if isinstance(v, list) else v.get('installed_version', 'unknown')
        vid = v[4] if isinstance(v, list) else v.get('vulnerability_id', 'unknown')
        adv = v[3] if isinstance(v, list) else v.get('advisory', 'Dependency vulnerability')
        out.append({
            'message': f'Vulnerable dependency: {pkg} ({ver}) - {adv}',
            'severity': 'high',
            'category': 'security',
            'line': 1,
            'file': '$req_file',
            'rule': f'safety-{vid}',
            'package': pkg,
            'installed_version': ver
        })
json.dump(out, sys.stdout)
" 2>/dev/null) || findings="[]"
      fi
      ;;
  esac

  local end_time
  end_time=$(date +%s.%N 2>/dev/null || python3 -c 'import time; print(time.time())')
  local runtime
  runtime=$(python3 -c "print(round($end_time - $start_time, 2))" 2>/dev/null || echo "0.0")

  echo "{\"tool\":\"$tool\",\"version\":\"$version\",\"findings\":$findings,\"exit_code\":${exit_code:-0},\"runtime_seconds\":$runtime}"
}

TOOLS=(bandit pylint flake8 mypy safety)

echo "["
first=true
for tool in "${TOOLS[@]}"; do
  if ! command -v "$tool" &>/dev/null; then
    echo "Skipping $tool: not installed" >&2
    continue
  fi

  if [[ "$first" == "true" ]]; then
    first=false
  else
    echo ","
  fi

  run_tool "$tool" "${FILES[@]}"
done
echo "]"
