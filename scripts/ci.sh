#!/usr/bin/env bash
set -euo pipefail

TULA_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_ROOT="."
PROFILE="default"
PROFILE_EXPLICIT=false
THRESHOLD=""
THRESHOLD_EXPLICIT=false
FORMAT="json"
DIFF_REF=""
DETERMINISTIC=false
OUTPUT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile) PROFILE="$2"; PROFILE_EXPLICIT=true; shift 2 ;;
    --threshold) THRESHOLD="$2"; THRESHOLD_EXPLICIT=true; shift 2 ;;
    --format) FORMAT="$2"; shift 2 ;;
    --diff) DIFF_REF="$2"; shift 2 ;;
    --output) OUTPUT="$2"; shift 2 ;;
    --deterministic) DETERMINISTIC=true; shift ;;
    --project-root) PROJECT_ROOT="$2"; shift 2 ;;
    *) PROJECT_ROOT="$1"; shift ;;
  esac
done

PROJECT_ROOT=$(cd "$PROJECT_ROOT" && pwd)

if ! command -v jq &>/dev/null; then
  echo "Error: jq is required" >&2
  exit 3
fi

# Load scoring config
SCORING_FILE="$TULA_ROOT/rules/_scoring.yml"
if ! [[ -f "$SCORING_FILE" ]]; then
  echo "Error: scoring config not found at $SCORING_FILE" >&2
  exit 3
fi

# Extract profile thresholds using python3 or grep fallback
get_yaml_value() {
  local file="$1" key="$2"
  if command -v python3 &>/dev/null; then
    python3 -c "
import yaml, sys
with open('$file') as f:
    d = yaml.safe_load(f)
keys = '$key'.split('.')
for k in keys:
    if isinstance(d, dict):
        d = d.get(k, {})
    else:
        d = {}
print(d if not isinstance(d, dict) else '')
" 2>/dev/null
  else
    grep -A1 "$key" "$file" 2>/dev/null | tail -1 | sed 's/.*: //' | tr -d ' '
  fi
}

# Resolve threshold from profile if not overridden
if [[ -z "$THRESHOLD" ]]; then
  THRESHOLD=$(get_yaml_value "$SCORING_FILE" "profiles.$PROFILE.thresholds.pass")
  if [[ -z "$THRESHOLD" || "$THRESHOLD" == "{}" ]]; then
    THRESHOLD=800
  fi
fi

echo "Tula CI — profile: $PROFILE, threshold: $THRESHOLD" >&2

# Phase 1: Detect
detect_output=$("$TULA_ROOT/scripts/detect.sh" "$PROJECT_ROOT" 2>/dev/null)
if [[ -z "$detect_output" ]]; then
  echo "Error: language detection failed" >&2
  exit 3
fi

# Auto-switch to docs profile for docs-only repos
detected_primary=$(echo "$detect_output" | jq -r '.primary // ""' 2>/dev/null)
if [[ "$detected_primary" == "docs" && "$PROFILE_EXPLICIT" == "false" ]]; then
  PROFILE="docs"
  if [[ "$THRESHOLD_EXPLICIT" == "false" ]]; then
    THRESHOLD=$(get_yaml_value "$SCORING_FILE" "profiles.docs.thresholds.pass")
    if [[ -z "$THRESHOLD" || "$THRESHOLD" == "{}" ]]; then
      THRESHOLD=700
    fi
  fi
fi

languages=$(echo "$detect_output" | jq -r '.languages | keys[]' 2>/dev/null)
if [[ -z "$languages" && "$detected_primary" != "docs" ]]; then
  echo "No supported languages detected in $PROJECT_ROOT" >&2
  exit 3
fi

echo "Languages detected: $languages" >&2

# Phase 2: Scan
all_findings='[]'
tools_used='[]'
tools_missing='[]'
total_runtime=0

for lang in $languages; do
  script="$TULA_ROOT/scripts/scan-${lang}.sh"
  if [[ ! -x "$script" ]]; then
    echo "Warning: no scan script for $lang" >&2
    continue
  fi

  scan_args=("--project-root" "$PROJECT_ROOT")
  if [[ -n "$DIFF_REF" ]]; then
    changed_files=$(cd "$PROJECT_ROOT" && git diff --name-only "$DIFF_REF" 2>/dev/null || true)
    if [[ -n "$changed_files" ]]; then
      scan_args=("--files" $changed_files)
    fi
  fi

  scan_output=$("$script" "${scan_args[@]}" 2>/dev/null || echo '[]')

  tool_count=$(echo "$scan_output" | jq 'length' 2>/dev/null || echo 0)
  for i in $(seq 0 $((tool_count - 1))); do
    tool_name=$(echo "$scan_output" | jq -r ".[$i].tool // \"unknown\"")
    tool_version=$(echo "$scan_output" | jq -r ".[$i].version // \"unknown\"")
    tool_findings=$(echo "$scan_output" | jq ".[$i].findings // []")
    tool_runtime=$(echo "$scan_output" | jq ".[$i].runtime_seconds // 0")

    finding_count=$(echo "$tool_findings" | jq 'length')
    if [[ "$finding_count" -gt 0 ]]; then
      all_findings=$(echo "$all_findings" | jq --argjson f "$tool_findings" '. + $f')
    fi

    tools_used=$(echo "$tools_used" | jq --arg t "$tool_name" --arg v "$tool_version" \
      '. + [{"tool": $t, "version": $v}]')
    total_runtime=$(echo "$total_runtime + $tool_runtime" | bc 2>/dev/null || echo "$total_runtime")
  done
done

# Run documentation scan
doc_output=$("$TULA_ROOT/scripts/scan-docs.sh" --project-root "$PROJECT_ROOT" 2>/dev/null || echo '{"findings":[]}')
doc_findings=$(echo "$doc_output" | jq '.findings // []')
doc_count=$(echo "$doc_findings" | jq 'length')
if [[ "$doc_count" -gt 0 ]]; then
  all_findings=$(echo "$all_findings" | jq --argjson f "$doc_findings" '. + $f')
fi

# Phase 3: Score (deterministic mode)
total_findings=$(echo "$all_findings" | jq 'length')

# Count by severity
critical=$(echo "$all_findings" | jq '[.[] | select(.severity_raw == "critical" or .severity_raw == "CRITICAL")] | length')
high=$(echo "$all_findings" | jq '[.[] | select(.severity_raw == "high" or .severity_raw == "HIGH" or .severity_raw == "error")] | length')
medium=$(echo "$all_findings" | jq '[.[] | select(.severity_raw == "medium" or .severity_raw == "MEDIUM" or .severity_raw == "warning")] | length')
low=$(echo "$all_findings" | jq '[.[] | select(.severity_raw == "low" or .severity_raw == "LOW" or .severity_raw == "style" or .severity_raw == "convention" or .severity_raw == "refactor")] | length')

# Category-weighted scoring: each finding's severity penalty is multiplied by its category weight
# Read severity penalties and category weights from _scoring.yml
sev_critical=$(get_yaml_value "$SCORING_FILE" "severity_penalties.critical")
sev_high=$(get_yaml_value "$SCORING_FILE" "severity_penalties.high")
sev_medium=$(get_yaml_value "$SCORING_FILE" "severity_penalties.medium")
sev_low=$(get_yaml_value "$SCORING_FILE" "severity_penalties.low")
sev_critical="${sev_critical:-200}"; sev_high="${sev_high:-100}"
sev_medium="${sev_medium:-25}"; sev_low="${sev_low:-5}"

# Profile-specific overrides
profile_sev_critical=$(get_yaml_value "$SCORING_FILE" "profiles.$PROFILE.severity_penalties.critical")
profile_sev_high=$(get_yaml_value "$SCORING_FILE" "profiles.$PROFILE.severity_penalties.high")
[[ -n "$profile_sev_critical" && "$profile_sev_critical" != "{}" ]] && sev_critical="$profile_sev_critical"
[[ -n "$profile_sev_high" && "$profile_sev_high" != "{}" ]] && sev_high="$profile_sev_high"

# Compute weighted penalty per finding using jq
score=$(echo "$all_findings" | jq --arg profile "$PROFILE" --arg scoring_file "$SCORING_FILE" \
  --argjson sev_crit "$sev_critical" --argjson sev_high "$sev_high" \
  --argjson sev_med "$sev_medium" --argjson sev_low "$sev_low" '
  def category_weight(cat):
    if cat == "security" then 1.5
    elif cat == "reliability" then 1.2
    elif cat == "performance" then 1.0
    elif cat == "maintainability" then 0.8
    elif cat == "documentation" then 0.6
    else 1.0
    end;
  def severity_penalty(sev):
    if sev == "critical" or sev == "CRITICAL" then $sev_crit
    elif sev == "high" or sev == "HIGH" or sev == "error" then $sev_high
    elif sev == "medium" or sev == "MEDIUM" or sev == "warning" then $sev_med
    elif sev == "low" or sev == "LOW" or sev == "style" or sev == "convention" or sev == "refactor" then $sev_low
    else 0
    end;
  1000 - ([.[] | severity_penalty(.severity_raw) * category_weight(.category // "maintainability")] | add // 0)
  | if . < 0 then 0 elif . > 1000 then 1000 else . end
  | floor
')
score="${score:-1000}"
[[ "$score" =~ ^-?[0-9]+$ ]] || score=1000
if [[ "$score" -lt 0 ]]; then score=0; fi
if [[ "$score" -gt 1000 ]]; then score=1000; fi

# Determine result
if [[ "$score" -ge "$THRESHOLD" && "$medium" -eq 0 && "$high" -eq 0 && "$critical" -eq 0 ]]; then
  result="PASS"
  exit_code=0
elif [[ "$score" -ge "$THRESHOLD" ]]; then
  result="WARN"
  exit_code=1
else
  result="FAIL"
  exit_code=2
fi

# Phase 4: Report
report=$(jq -n \
  --argjson score "$score" \
  --arg profile "$PROFILE" \
  --argjson threshold "$THRESHOLD" \
  --arg result "$result" \
  --argjson critical "$critical" \
  --argjson high "$high" \
  --argjson medium "$medium" \
  --argjson low "$low" \
  --argjson total "$total_findings" \
  --argjson tools "$tools_used" \
  --argjson findings "$all_findings" \
  --argjson runtime "$total_runtime" \
  '{
    score: $score,
    profile: $profile,
    threshold: $threshold,
    result: $result,
    issues: {
      total: $total,
      critical: $critical,
      high: $high,
      medium: $medium,
      low: $low
    },
    tools: $tools,
    findings: $findings,
    runtime_seconds: $runtime
  }')

if [[ "$FORMAT" == "text" ]]; then
  echo "Tula: $score/1000 [$PROFILE]"
  echo "Issues: $critical critical | $high high | $medium medium | $low low"
  echo "Threshold: $THRESHOLD — $result"
  echo "Tools: $(echo "$tools_used" | jq -r '.[].tool' | tr '\n' ', ' | sed 's/,$//')"
elif [[ "$FORMAT" == "json" ]]; then
  if [[ -n "$OUTPUT" ]]; then
    echo "$report" > "$OUTPUT"
    echo "Report written to $OUTPUT" >&2
  else
    echo "$report"
  fi
fi

echo "Result: $result (score: $score, threshold: $THRESHOLD)" >&2
exit "$exit_code"
