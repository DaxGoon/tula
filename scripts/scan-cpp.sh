#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=""
FILES=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-root) PROJECT_ROOT="$2"; shift 2 ;;
    --files) shift; while [[ $# -gt 0 && ! "$1" =~ ^-- ]]; do FILES+=("$1"); shift; done ;;
    *) shift ;;
  esac
done

if [[ -z "$PROJECT_ROOT" ]]; then
  PROJECT_ROOT="$(pwd)"
fi

if [[ ${#FILES[@]} -eq 0 ]]; then
  while IFS= read -r f; do
    FILES+=("$f")
  done < <(find "$PROJECT_ROOT" \( -name '*.c' -o -name '*.h' -o -name '*.cpp' -o -name '*.cxx' -o -name '*.cc' -o -name '*.hpp' -o -name '*.hxx' \) \
    -not -path '*/.git/*' -not -path '*/build/*' -not -path '*/vendor/*' -not -path '*/third_party/*' -not -path '*/node_modules/*' 2>/dev/null)
fi

if [[ ${#FILES[@]} -eq 0 ]]; then
  echo '[]'
  exit 0
fi

RESULTS=()

get_time_ns() {
  python3 -c 'import time; print(int(time.time()*1e9))' 2>/dev/null || date +%s
}

calc_runtime() {
  local start="$1" end="$2"
  echo "scale=2; ($end - $start) / 1000000000" | bc 2>/dev/null || echo "0.0"
}

# --- clang-tidy ---
if command -v clang-tidy &>/dev/null; then
  CT_VER=$(clang-tidy --version 2>/dev/null | head -1 | sed 's/.*version \([0-9][0-9.]*\).*/\1/')
  CT_FINDINGS='[]'
  CT_EXIT=0
  CT_START=$(get_time_ns)

  for file in "${FILES[@]}"; do
    output=$(clang-tidy "$file" \
      --checks='readability-*,modernize-*,performance-*,bugprone-*,security-*' \
      -- 2>/dev/null) || CT_EXIT=$?

    while IFS= read -r line; do
      if [[ "$line" =~ ^(.+):([0-9]+):([0-9]+):\ (error|warning):\ (.+)\ \[([^\]]+)\]$ ]]; then
        ct_sev="${BASH_REMATCH[4]}"
        ct_rule="${BASH_REMATCH[6]}"

        case "$ct_sev" in
          error) norm_sev="high" ;; *) norm_sev="medium" ;;
        esac
        case "$ct_rule" in
          bugprone-*) norm_cat="reliability" ;;
          performance-*) norm_cat="performance" ;;
          security-*) norm_cat="security" ;;
          *) norm_cat="maintainability" ;;
        esac

        CT_FINDINGS=$(echo "$CT_FINDINGS" | jq -c \
          --arg f "${BASH_REMATCH[1]}" --argjson l "${BASH_REMATCH[2]}" \
          --arg s "$norm_sev" --arg cat "$norm_cat" \
          --arg m "${BASH_REMATCH[5]}" --arg r "$ct_rule" \
          '. += [{"file":$f,"line":$l,"severity":$s,"category":$cat,"message":$m,"rule":$r}]')
      fi
    done <<< "$output"
  done

  CT_END=$(get_time_ns)
  RESULTS+=("$(jq -nc --arg tool "clang-tidy" --arg ver "$CT_VER" \
    --argjson findings "$CT_FINDINGS" --argjson exit "$CT_EXIT" \
    --arg rt "$(calc_runtime "$CT_START" "$CT_END")" \
    '{tool:$tool,version:$ver,findings:$findings,exit_code:$exit,runtime_seconds:($rt|tonumber)}')")
fi

# --- cppcheck ---
if command -v cppcheck &>/dev/null; then
  CP_VER=$(cppcheck --version 2>/dev/null | sed 's/Cppcheck //')
  CP_FINDINGS='[]'
  CP_EXIT=0
  CP_START=$(get_time_ns)

  for file in "${FILES[@]}"; do
    xml_output=$(cppcheck --xml --xml-version=2 --enable=all "$file" 2>&1 1>/dev/null) || CP_EXIT=$?

    cp_id="" cp_sev="" cp_msg=""
    while IFS= read -r err_line; do
      if [[ "$err_line" =~ \<error ]]; then
        cp_id=$(echo "$err_line" | sed -n 's/.*id="\([^"]*\)".*/\1/p')
        cp_sev=$(echo "$err_line" | sed -n 's/.*severity="\([^"]*\)".*/\1/p')
        cp_msg=$(echo "$err_line" | sed -n 's/.*msg="\([^"]*\)".*/\1/p')
      fi
      if [[ "$err_line" =~ \<location ]]; then
        cp_file=$(echo "$err_line" | sed -n 's/.*file="\([^"]*\)".*/\1/p')
        cp_line=$(echo "$err_line" | sed -n 's/.*line="\([^"]*\)".*/\1/p')

        case "$cp_sev" in
          error) norm_sev="high" ;; warning|performance) norm_sev="medium" ;; *) norm_sev="low" ;;
        esac

        cp_id_lower=$(echo "$cp_id" | tr '[:upper:]' '[:lower:]')
        norm_cat="maintainability"
        case "$cp_id_lower" in
          *buffer*|*overflow*|*null*|*memory*) norm_cat="security" ;;
          *performance*|*inefficient*|*slow*) norm_cat="performance" ;;
          *leak*|*crash*|*undefined*|*error*) norm_cat="reliability" ;;
        esac

        if [[ -n "$cp_id" && "$cp_id" != "missingIncludeSystem" ]]; then
          CP_FINDINGS=$(echo "$CP_FINDINGS" | jq -c \
            --arg f "$cp_file" --argjson l "${cp_line:-0}" \
            --arg s "$norm_sev" --arg cat "$norm_cat" \
            --arg m "$cp_msg" --arg r "$cp_id" \
            '. += [{"file":$f,"line":$l,"severity":$s,"category":$cat,"message":$m,"rule":$r}]')
        fi
      fi
    done <<< "$xml_output"
  done

  CP_END=$(get_time_ns)
  RESULTS+=("$(jq -nc --arg tool "cppcheck" --arg ver "$CP_VER" \
    --argjson findings "$CP_FINDINGS" --argjson exit "$CP_EXIT" \
    --arg rt "$(calc_runtime "$CP_START" "$CP_END")" \
    '{tool:$tool,version:$ver,findings:$findings,exit_code:$exit,runtime_seconds:($rt|tonumber)}')")
fi

# --- pattern scanning ---
PAT_FINDINGS='[]'
PAT_START=$(get_time_ns)

run_pattern() {
  local pat_id="$1" pattern="$2" severity="$3" category="$4" message="$5" flags="${6:-}"

  for file in "${FILES[@]}"; do
    local grep_args=("-nE")
    if [[ -n "$flags" ]]; then grep_args+=("$flags"); fi

    while IFS=: read -r match_line _rest; do
      if [[ -n "$match_line" ]]; then
        PAT_FINDINGS=$(echo "$PAT_FINDINGS" | jq -c \
          --arg f "$file" --argjson l "$match_line" \
          --arg s "$severity" --arg cat "$category" \
          --arg m "$message" --arg r "$pat_id" \
          '. += [{"file":$f,"line":$l,"severity":$s,"category":$cat,"message":$m,"rule":$r}]')
      fi
    done < <(grep "${grep_args[@]}" "$pattern" "$file" 2>/dev/null || true)
  done
}

run_pattern "unsafe-string-function" '\b(strcpy|strcat|sprintf|gets)\s*\(' "high" "security" \
  "Unsafe string function -- use safer alternatives (strncpy, strncat, snprintf, fgets)"
run_pattern "format-string-vuln" '\bprintf\s*\(\s*[a-zA-Z_][a-zA-Z0-9_]*\s*\)' "high" "security" \
  "Potential format string vulnerability -- use explicit format specifiers"
run_pattern "hardcoded-secret" '(password|secret|key|token)\s*=\s*"[^"]{8,}"' "high" "security" \
  "Potential hardcoded secret -- use secure storage" "-i"
run_pattern "insecure-random" '\brand\s*\(\s*\)' "medium" "security" \
  "rand() is not cryptographically secure -- consider arc4random or CSPRNG"
run_pattern "malloc-check" '\bmalloc\s*\(' "medium" "reliability" \
  "malloc() used -- ensure free() and null-check the return value"
run_pattern "todo-comment" '//.*\b(TODO|FIXME|HACK|XXX)\b' "low" "maintainability" \
  "TODO/FIXME comment found" "-i"

# Threshold: deep nesting (>5 brace levels)
for file in "${FILES[@]}"; do
  nesting=0
  line_num=0
  while IFS= read -r src_line; do
    line_num=$((line_num + 1))
    opens=$(echo "$src_line" | tr -cd '{' | wc -c | tr -d ' ')
    closes=$(echo "$src_line" | tr -cd '}' | wc -c | tr -d ' ')
    nesting=$((nesting + opens - closes))
    if [[ $nesting -gt 5 ]]; then
      PAT_FINDINGS=$(echo "$PAT_FINDINGS" | jq -c \
        --arg f "$file" --argjson l "$line_num" --arg s "medium" --arg cat "maintainability" \
        --arg m "Deep nesting (level $nesting) -- extract functions or use early returns" \
        --arg r "deep-nesting" \
        '. += [{"file":$f,"line":$l,"severity":$s,"category":$cat,"message":$m,"rule":$r}]')
    fi
  done < "$file"

  # Threshold: line too long (>120)
  line_num=0
  while IFS= read -r src_line; do
    line_num=$((line_num + 1))
    if [[ ${#src_line} -gt 120 ]]; then
      PAT_FINDINGS=$(echo "$PAT_FINDINGS" | jq -c \
        --arg f "$file" --argjson l "$line_num" --arg s "low" --arg cat "maintainability" \
        --arg m "Line exceeds 120 characters (${#src_line})" --arg r "line-too-long" \
        '. += [{"file":$f,"line":$l,"severity":$s,"category":$cat,"message":$m,"rule":$r}]')
    fi
  done < "$file"
done

PAT_END=$(get_time_ns)
RESULTS+=("$(jq -nc --arg tool "pattern-scan" --arg ver "1.0.0" \
  --argjson findings "$PAT_FINDINGS" --argjson exit 0 \
  --arg rt "$(calc_runtime "$PAT_START" "$PAT_END")" \
  '{tool:$tool,version:$ver,findings:$findings,exit_code:$exit,runtime_seconds:($rt|tonumber)}')")

# --- emit JSON array ---
printf '['
first=true
for r in "${RESULTS[@]}"; do
  if [[ "$first" == "true" ]]; then first=false; else printf ','; fi
  printf '%s' "$r"
done
printf ']\n'
