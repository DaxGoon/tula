#!/usr/bin/env bash
set -euo pipefail

ROOT="."
FILES=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-root) ROOT="$2"; shift 2 ;;
    --files) shift; while [[ $# -gt 0 && ! "$1" =~ ^-- ]]; do FILES+=("$1"); shift; done ;;
    *) shift ;;
  esac
done

ROOT=$(cd "$ROOT" && pwd)

findings='[]'
metrics='{}'

emit_finding() {
  local id="$1" message="$2" severity="$3" category="${4:-documentation}" file="${5:-project-root}" line="${6:-0}"
  findings=$(echo "$findings" | jq \
    --arg id "$id" --arg msg "$message" --arg sev "$severity" \
    --arg cat "$category" --arg file "$file" --argjson line "$line" \
    '. + [{"rule": $id, "message": $msg, "severity_raw": $sev, "category": $cat, "file": $file, "line": $line}]')
}

check_file_exists() {
  local id="$1" message="$2" severity="$3"
  shift 3
  local paths=("$@")
  for p in "${paths[@]}"; do
    if [[ -f "$ROOT/$p" ]]; then
      return 0
    fi
  done
  emit_finding "$id" "$message" "$severity"
  return 1
}

check_file_exists "DOC-README-001" "No README file found in project root" "high" \
  README.md README.rst README.txt README || true

check_file_exists "DOC-CHANGELOG-001" "No CHANGELOG file found" "low" \
  CHANGELOG.md CHANGELOG.rst CHANGELOG.txt CHANGELOG CHANGES.md HISTORY.md || true

check_file_exists "DOC-CONTRIB-001" "No CONTRIBUTING guide found" "low" \
  CONTRIBUTING.md CONTRIBUTING.rst .github/CONTRIBUTING.md || true

check_file_exists "DOC-LICENCE-001" "No licence file found" "medium" \
  LICENSE LICENSE.md LICENSE.txt LICENCE LICENCE.md LICENCE.txt || true

# --- Docs directory detection ---
docs_directory=false
for d in docs doc; do
  if [[ -d "$ROOT/$d" ]]; then
    docs_directory=true
    break
  fi
done
metrics=$(echo "$metrics" | jq --argjson v "$docs_directory" '. + {"docs_directory": $v}')

# --- API spec file detection ---
api_spec=false
for spec in openapi.yml openapi.yaml swagger.json swagger.yml api-spec.yml api-spec.yaml; do
  if [[ -f "$ROOT/$spec" ]]; then
    api_spec=true
    break
  fi
done
if [[ "$api_spec" == "false" && -d "$ROOT/docs" ]]; then
  for spec in openapi.yml openapi.yaml swagger.json swagger.yml; do
    if [[ -f "$ROOT/docs/$spec" ]]; then
      api_spec=true
      break
    fi
  done
fi
metrics=$(echo "$metrics" | jq --argjson v "$api_spec" '. + {"api_spec": $v}')

# --- Python docstring coverage ---
DOC_FILE_LIMIT="${MATRA_DOC_FILE_LIMIT:-200}"

py_files=$(find "$ROOT" -name "*.py" \
  -not -path "*/.git/*" \
  -not -path "*/.venv/*" \
  -not -path "*/venv/*" \
  -not -path "*/node_modules/*" \
  -not -path "*/__pycache__/*" \
  -not -path "*/test*" \
  2>/dev/null || true)

if [[ -n "$py_files" ]] && command -v python3 &>/dev/null; then
  py_coverage=$(echo "$py_files" | head -"$DOC_FILE_LIMIT" | tr '\n' '\0' | xargs -0 python3 -c "
import ast, sys
total = documented = 0
for f in sys.argv[1:]:
    try:
        tree = ast.parse(open(f).read())
        for node in ast.walk(tree):
            if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
                if not node.name.startswith('_'):
                    total += 1
                    if (node.body and isinstance(node.body[0], ast.Expr)
                        and isinstance(node.body[0].value, ast.Constant)
                        and isinstance(node.body[0].value.value, str)):
                        documented += 1
    except: pass
pct = int(documented / total * 100) if total > 0 else 100
print(f'{documented}/{total}/{pct}')
" 2>/dev/null || echo "0/0/100")

  IFS='/' read -r doc total pct <<< "$py_coverage"
  doc="${doc:-0}"; total="${total:-0}"; pct="${pct:-100}"
  [[ "$doc" =~ ^[0-9]+$ ]] || doc=0
  [[ "$total" =~ ^[0-9]+$ ]] || total=0
  [[ "$pct" =~ ^[0-9]+$ ]] || pct=100
  metrics=$(echo "$metrics" | jq \
    --argjson doc "$doc" --argjson total "$total" --argjson pct "$pct" \
    '. + {"python": {"documented": $doc, "total": $total, "coverage_pct": $pct}}')

  if [[ "$total" -gt 0 ]]; then
    if [[ "$pct" -gt 70 ]]; then
      emit_finding "DOC-API-001" "Python docstring coverage is ${pct}% — over-documented, prefer self-explanatory names" "medium"
    elif [[ "$pct" -gt 50 ]]; then
      emit_finding "DOC-API-001" "Python docstring coverage is ${pct}% — mildly verbose" "low"
    fi
  fi
fi

# --- Go doc-comment coverage ---
go_files=$(find "$ROOT" -name "*.go" \
  -not -path "*/.git/*" \
  -not -path "*/vendor/*" \
  -not -path "*/test*" \
  2>/dev/null || true)

if [[ -n "$go_files" ]]; then
  go_total=0
  go_documented=0
  while IFS= read -r gf; do
    [[ -f "$gf" ]] || continue
    prev_line=""
    while IFS= read -r line; do
      if echo "$line" | grep -qE '^func [A-Z]|^type [A-Z]|^var [A-Z]|^const [A-Z]'; then
        go_total=$((go_total + 1))
        if echo "$prev_line" | grep -qE '^//'; then
          go_documented=$((go_documented + 1))
        fi
      fi
      prev_line="$line"
    done < "$gf"
  done <<< "$go_files"

  go_pct=100
  if [[ "$go_total" -gt 0 ]]; then
    go_pct=$((go_documented * 100 / go_total))
  fi
  metrics=$(echo "$metrics" | jq \
    --argjson doc "$go_documented" --argjson total "$go_total" --argjson pct "$go_pct" \
    '. + {"go": {"documented": $doc, "total": $total, "coverage_pct": $pct}}')
fi

# --- JS/TS JSDoc coverage ---
js_files=$(find "$ROOT" \( -name "*.js" -o -name "*.jsx" -o -name "*.ts" -o -name "*.tsx" -o -name "*.mjs" \) \
  -not -path "*/.git/*" \
  -not -path "*/node_modules/*" \
  -not -path "*/dist/*" \
  -not -path "*/build/*" \
  -not -path "*/test*" \
  2>/dev/null || true)

if [[ -n "$js_files" ]]; then
  js_total=0
  js_documented=0
  while IFS= read -r jsf; do
    [[ -f "$jsf" ]] || continue
    prev_line=""
    while IFS= read -r line; do
      if echo "$line" | grep -qE '^\s*(export\s+)?(function|class|const|let|var)\s+[A-Za-z]'; then
        js_total=$((js_total + 1))
        if echo "$prev_line" | grep -qE '^\s*\*/' ; then
          js_documented=$((js_documented + 1))
        fi
      fi
      prev_line="$line"
    done < "$jsf"
  done <<< "$js_files"

  js_pct=100
  if [[ "$js_total" -gt 0 ]]; then
    js_pct=$((js_documented * 100 / js_total))
  fi
  metrics=$(echo "$metrics" | jq \
    --argjson doc "$js_documented" --argjson total "$js_total" --argjson pct "$js_pct" \
    '. + {"javascript": {"documented": $doc, "total": $total, "coverage_pct": $pct}}')
fi

# --- Java Javadoc coverage ---
java_files=$(find "$ROOT" -name "*.java" \
  -not -path "*/.git/*" \
  -not -path "*/build/*" \
  -not -path "*/target/*" \
  -not -path "*/test*" \
  2>/dev/null || true)

if [[ -n "$java_files" ]]; then
  java_total=0
  java_documented=0
  while IFS= read -r jf; do
    [[ -f "$jf" ]] || continue
    prev_line=""
    while IFS= read -r line; do
      if echo "$line" | grep -qE '^\s*public\s+(class|interface|enum|void|int|String|boolean|long|double|float|Object|static)'; then
        java_total=$((java_total + 1))
        if echo "$prev_line" | grep -qE '^\s*\*/' ; then
          java_documented=$((java_documented + 1))
        fi
      fi
      prev_line="$line"
    done < "$jf"
  done <<< "$java_files"

  java_pct=100
  if [[ "$java_total" -gt 0 ]]; then
    java_pct=$((java_documented * 100 / java_total))
  fi
  metrics=$(echo "$metrics" | jq \
    --argjson doc "$java_documented" --argjson total "$java_total" --argjson pct "$java_pct" \
    '. + {"java": {"documented": $doc, "total": $total, "coverage_pct": $pct}}')
fi

# --- README metrics with heading-based section detection ---
readme_file=""
for rf in README.md README.rst README.txt README; do
  if [[ -f "$ROOT/$rf" ]]; then
    readme_file="$ROOT/$rf"
    break
  fi
done

if [[ -n "$readme_file" ]]; then
  line_count=$(wc -l < "$readme_file" | tr -d ' ')
  word_count=$(wc -w < "$readme_file" | tr -d ' ')

  has_install=false
  has_usage=false
  has_api=false
  has_config=false

  while IFS= read -r line; do
    heading=$(echo "$line" | sed -n 's/^## *//p' | tr '[:upper:]' '[:lower:]' | sed 's/[[:space:]]*$//')
    case "$heading" in
      install*) has_install=true ;;
      usage*|getting\ started*|example*) has_usage=true ;;
      api*) has_api=true ;;
      config*|settings*) has_config=true ;;
    esac
  done < "$readme_file"

  metrics=$(echo "$metrics" | jq \
    --argjson lines "$line_count" \
    --argjson words "$word_count" \
    --argjson install "$has_install" \
    --argjson usage "$has_usage" \
    --argjson api "$has_api" \
    --argjson config "$has_config" \
    '. + {"readme": {"lines": $lines, "words": $words, "has_install_section": $install, "has_usage_section": $usage, "has_api_section": $api, "has_config_section": $config}}')

  missing_sections=""
  if [[ "$has_install" == "false" ]]; then missing_sections+="Installation, "; fi
  if [[ "$has_usage" == "false" ]]; then missing_sections+="Usage, "; fi
  if [[ -n "$missing_sections" ]]; then
    missing_sections="${missing_sections%, }"
    emit_finding "DOC-README-002" "README missing key sections: $missing_sections" "medium"
  fi
fi

# --- Broken internal markdown links ---
md_files=$(find "$ROOT" -name "*.md" \
  -not -path "*/.git/*" \
  -not -path "*/node_modules/*" \
  -not -path "*/vendor/*" \
  2>/dev/null || true)

if [[ -n "$md_files" ]]; then
  broken_links_tmp=$(mktemp)
  while IFS= read -r mdf; do
    [[ -f "$mdf" ]] || continue
    md_dir=$(dirname "$mdf")
    rel_mdf="${mdf#"$ROOT"/}"
    while IFS= read -r match; do
      link_target=$(echo "$match" | sed 's/.*](\(.*\))/\1/' | sed 's/#.*//' | sed 's/?.*//')
      [[ -z "$link_target" ]] && continue
      [[ "$link_target" =~ ^https?:// ]] && continue
      [[ "$link_target" =~ ^mailto: ]] && continue
      [[ "$link_target" =~ ^# ]] && continue
      if [[ ! -e "$md_dir/$link_target" ]]; then
        echo "${rel_mdf}|${link_target}" >> "$broken_links_tmp"
      fi
    done < <(grep -oE '\[([^]]+)\]\(([^)]+)\)' "$mdf" 2>/dev/null || true)
  done <<< "$md_files"
  while IFS='|' read -r bl_file bl_target; do
    emit_finding "DOC-LINK-001" "Broken internal link: $bl_target" "medium" "documentation" "$bl_file" "0"
  done < "$broken_links_tmp"
  rm -f "$broken_links_tmp"
fi

# --- Age check for TODOs (DOC-INLINE-001) ---
if command -v git &>/dev/null && [[ -d "$ROOT/.git" ]]; then
  six_months_ago=$(date -v-6m +%s 2>/dev/null || date -d "6 months ago" +%s 2>/dev/null || echo "")
  if [[ -n "$six_months_ago" ]]; then
    todo_files=$(grep -rl 'TODO\|FIXME\|HACK\|XXX' "$ROOT" \
      --include="*.py" --include="*.go" --include="*.js" --include="*.ts" \
      --include="*.java" --include="*.c" --include="*.cpp" --include="*.h" \
      2>/dev/null | head -50 || true)
    if [[ -n "$todo_files" ]]; then
      stale_todos_tmp=$(mktemp)
      while IFS= read -r tf; do
        [[ -f "$tf" ]] || continue
        rel_tf="${tf#"$ROOT"/}"
        while IFS=: read -r lnum _rest; do
          blame_date=$(cd "$ROOT" && git blame -L "$lnum,$lnum" --porcelain "$rel_tf" 2>/dev/null | grep '^author-time' | awk '{print $2}' || echo "")
          if [[ -n "$blame_date" && "$blame_date" =~ ^[0-9]+$ && "$blame_date" -lt "$six_months_ago" ]]; then
            echo "${rel_tf}|${lnum}" >> "$stale_todos_tmp"
          fi
        done < <(grep -n 'TODO\|FIXME\|HACK\|XXX' "$tf" 2>/dev/null || true)
      done <<< "$todo_files"
      while IFS='|' read -r st_file st_line; do
        emit_finding "DOC-INLINE-001" "Stale TODO/FIXME older than 6 months" "low" "documentation" "$st_file" "$st_line"
      done < "$stale_todos_tmp"
      rm -f "$stale_todos_tmp"
    fi
  fi
fi

echo "{\"tool\":\"scan-docs\",\"version\":\"2.0\",\"findings\":$findings,\"metrics\":$metrics,\"exit_code\":0}"
