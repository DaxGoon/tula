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

# --- SpotBugs ---
if command -v spotbugs &>/dev/null; then
  SPOTBUGS_VERSION=$(spotbugs -version 2>/dev/null || echo "unknown")
  START=$(date +%s.%N)
  SPOTBUGS_OUTPUT=""
  SPOTBUGS_EXIT=0

  TMPXML=$(mktemp /tmp/spotbugs-XXXXXX.xml)
  trap "rm -f $TMPXML" EXIT

  spotbugs -textui -xml:withMessages -effort:max -output "$TMPXML" \
    $(get_file_args) 2>/dev/null || SPOTBUGS_EXIT=$?

  FINDINGS="[]"
  if [[ -f "$TMPXML" && -s "$TMPXML" ]]; then
    FINDINGS=$(python3 -c "
import xml.etree.ElementTree as ET, json, sys
tree = ET.parse('$TMPXML')
findings = []
for bug in tree.findall('.//BugInstance'):
    sl = bug.find('SourceLine')
    findings.append({
        'message': (bug.find('LongMessage').text if bug.find('LongMessage') is not None else bug.get('type','')),
        'severity_raw': bug.get('priority','3'),
        'line': int(sl.get('start','0')) if sl is not None else 0,
        'file': (sl.get('sourcepath','') if sl is not None else ''),
        'rule': bug.get('type','')
    })
json.dump(findings, sys.stdout)
" 2>/dev/null || echo "[]")
  fi

  END=$(date +%s.%N)
  RUNTIME=$(echo "$END - $START" | bc 2>/dev/null || echo "0")
  add_result "spotbugs" "$SPOTBUGS_VERSION" "$FINDINGS" "$SPOTBUGS_EXIT" "$RUNTIME"
  rm -f "$TMPXML"
  trap - EXIT
else
  echo "Warning: spotbugs not found, skipping" >&2
fi

# --- FindSecBugs (SpotBugs plugin) ---
if command -v spotbugs &>/dev/null; then
  FINDSECBUGS_JAR=""
  for candidate in \
    "$HOME/.spotbugs/plugin/findsecbugs-plugin.jar" \
    "/usr/local/share/spotbugs/plugin/findsecbugs-plugin.jar" \
    "$PROJECT_ROOT/config/findsecbugs-plugin.jar"; do
    if [[ -f "$candidate" ]]; then
      FINDSECBUGS_JAR="$candidate"
      break
    fi
  done

  if [[ -n "$FINDSECBUGS_JAR" ]]; then
    START=$(date +%s.%N)
    TMPXML=$(mktemp /tmp/findsecbugs-XXXXXX.xml)
    FINDSECBUGS_EXIT=0

    spotbugs -textui -xml:withMessages -effort:max -pluginList "$FINDSECBUGS_JAR" \
      -output "$TMPXML" $(get_file_args) 2>/dev/null || FINDSECBUGS_EXIT=$?

    FINDINGS="[]"
    if [[ -f "$TMPXML" && -s "$TMPXML" ]]; then
      FINDINGS=$(python3 -c "
import xml.etree.ElementTree as ET, json, sys
tree = ET.parse('$TMPXML')
findings = []
for bug in tree.findall('.//BugInstance'):
    if bug.get('category','') in ('SECURITY','MALICIOUS_CODE'):
        sl = bug.find('SourceLine')
        findings.append({
            'message': (bug.find('LongMessage').text if bug.find('LongMessage') is not None else bug.get('type','')),
            'severity_raw': bug.get('priority','3'),
            'line': int(sl.get('start','0')) if sl is not None else 0,
            'file': (sl.get('sourcepath','') if sl is not None else ''),
            'rule': bug.get('type','')
        })
json.dump(findings, sys.stdout)
" 2>/dev/null || echo "[]")
    fi

    END=$(date +%s.%N)
    RUNTIME=$(echo "$END - $START" | bc 2>/dev/null || echo "0")
    add_result "findsecbugs" "spotbugs-plugin" "$FINDINGS" "$FINDSECBUGS_EXIT" "$RUNTIME"
    rm -f "$TMPXML"
  else
    echo "Warning: findsecbugs plugin JAR not found, skipping" >&2
  fi
fi

# --- PMD ---
if command -v pmd &>/dev/null; then
  PMD_VERSION=$(pmd --version 2>/dev/null | head -1 || echo "unknown")
  START=$(date +%s.%N)
  PMD_OUTPUT=""
  PMD_EXIT=0
  PMD_OUTPUT=$(pmd check -f json -d "$(get_file_args)" \
    -R rulesets/java/quickstart.xml 2>/dev/null) || PMD_EXIT=$?

  FINDINGS="[]"
  if [[ -n "$PMD_OUTPUT" ]]; then
    FINDINGS=$(echo "$PMD_OUTPUT" | jq '[
      .files // [] | .[] | .filename as $file | .violations[] | {
        message: .message,
        severity_raw: (.priority | tostring),
        line: .beginLine,
        file: $file,
        rule: .rule
      }
    ]' 2>/dev/null || echo "[]")
  fi

  END=$(date +%s.%N)
  RUNTIME=$(echo "$END - $START" | bc 2>/dev/null || echo "0")
  add_result "pmd" "$PMD_VERSION" "$FINDINGS" "$PMD_EXIT" "$RUNTIME"
else
  echo "Warning: pmd not found, skipping" >&2
fi

# --- Checkstyle ---
if command -v checkstyle &>/dev/null; then
  CHECKSTYLE_VERSION=$(checkstyle --version 2>/dev/null | awk '{print $NF}' || echo "unknown")
  START=$(date +%s.%N)
  TMPXML=$(mktemp /tmp/checkstyle-XXXXXX.xml)
  CHECKSTYLE_EXIT=0

  checkstyle -c /google_checks.xml -f xml -o "$TMPXML" \
    $(get_file_args) 2>/dev/null || CHECKSTYLE_EXIT=$?

  FINDINGS="[]"
  if [[ -f "$TMPXML" && -s "$TMPXML" ]]; then
    FINDINGS=$(python3 -c "
import xml.etree.ElementTree as ET, json, sys
tree = ET.parse('$TMPXML')
findings = []
for f in tree.findall('.//file'):
    fname = f.get('name','')
    for err in f.findall('error'):
        findings.append({
            'message': err.get('message',''),
            'severity_raw': err.get('severity','warning'),
            'line': int(err.get('line','0')),
            'file': fname,
            'rule': err.get('source','').split('.')[-1] if err.get('source') else ''
        })
json.dump(findings, sys.stdout)
" 2>/dev/null || echo "[]")
  fi

  END=$(date +%s.%N)
  RUNTIME=$(echo "$END - $START" | bc 2>/dev/null || echo "0")
  add_result "checkstyle" "$CHECKSTYLE_VERSION" "$FINDINGS" "$CHECKSTYLE_EXIT" "$RUNTIME"
  rm -f "$TMPXML"
else
  echo "Warning: checkstyle not found, skipping" >&2
fi

# --- OWASP Dependency-Check ---
if command -v dependency-check &>/dev/null; then
  DC_VERSION=$(dependency-check --version 2>/dev/null | head -1 || echo "unknown")
  START=$(date +%s.%N)
  TMPDIR=$(mktemp -d /tmp/depcheck-XXXXXX)
  DC_EXIT=0

  dependency-check --project matra-scan --scan "$PROJECT_ROOT" \
    --format JSON --out "$TMPDIR" 2>/dev/null || DC_EXIT=$?

  FINDINGS="[]"
  REPORT="$TMPDIR/dependency-check-report.json"
  if [[ -f "$REPORT" ]]; then
    FINDINGS=$(jq '[
      .dependencies // [] | .[] | select(.vulnerabilities != null) |
      .fileName as $file | .vulnerabilities[] | {
        message: .description,
        severity_raw: .severity,
        line: 0,
        file: $file,
        rule: .name
      }
    ]' "$REPORT" 2>/dev/null || echo "[]")
  fi

  END=$(date +%s.%N)
  RUNTIME=$(echo "$END - $START" | bc 2>/dev/null || echo "0")
  add_result "owasp-dependency-check" "$DC_VERSION" "$FINDINGS" "$DC_EXIT" "$RUNTIME"
  rm -rf "$TMPDIR"
else
  echo "Warning: dependency-check not found, skipping" >&2
fi

echo "$RESULTS" | jq '.'
