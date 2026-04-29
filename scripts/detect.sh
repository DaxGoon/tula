#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"
ROOT=$(cd "$ROOT" && pwd)

count_files() {
  local ext="$1"
  find "$ROOT" -name "$ext" \
    -not -path "*/.git/*" \
    -not -path "*/node_modules/*" \
    -not -path "*/.venv/*" \
    -not -path "*/venv/*" \
    -not -path "*/vendor/*" \
    -not -path "*/third_party/*" \
    -not -path "*/build/*" \
    -not -path "*/dist/*" \
    -not -path "*/__pycache__/*" \
    2>/dev/null | wc -l | tr -d ' '
}

tools_json_array() {
  local tools_list=""
  for t in "$@"; do
    if command -v "$t" &>/dev/null; then
      if [[ -n "$tools_list" ]]; then tools_list+=","; fi
      tools_list+="\"$t\""
    fi
  done
  echo "[$tools_list]"
}

languages='{}'
tools='{}'
primary=""
max_count=0

# Python
py_count=$(count_files "*.py")
if [[ "$py_count" -gt 0 ]]; then
  languages=$(echo "$languages" | jq --argjson c "$py_count" '.python = $c')
  py_tools=$(tools_json_array bandit pylint flake8 mypy safety)
  tools=$(echo "$tools" | jq --argjson t "$py_tools" '.python = $t')
  if [[ "$py_count" -gt "$max_count" ]]; then max_count=$py_count; primary="python"; fi
fi

# JavaScript / TypeScript
js_count=0
for ext in "*.js" "*.jsx" "*.mjs" "*.ts" "*.tsx"; do
  n=$(count_files "$ext")
  js_count=$((js_count + n))
done
if [[ "$js_count" -gt 0 ]]; then
  languages=$(echo "$languages" | jq --argjson c "$js_count" '.javascript = $c')
  js_tools=$(tools_json_array eslint tsc npx node npm)
  tools=$(echo "$tools" | jq --argjson t "$js_tools" '.javascript = $t')
  if [[ "$js_count" -gt "$max_count" ]]; then max_count=$js_count; primary="javascript"; fi
fi

# Java
java_count=$(count_files "*.java")
if [[ "$java_count" -gt 0 ]]; then
  languages=$(echo "$languages" | jq --argjson c "$java_count" '.java = $c')
  java_tools=$(tools_json_array spotbugs pmd checkstyle)
  tools=$(echo "$tools" | jq --argjson t "$java_tools" '.java = $t')
  if [[ "$java_count" -gt "$max_count" ]]; then max_count=$java_count; primary="java"; fi
fi

# Go
go_count=$(count_files "*.go")
if [[ "$go_count" -gt 0 ]]; then
  languages=$(echo "$languages" | jq --argjson c "$go_count" '.go = $c')
  go_tools=$(tools_json_array golangci-lint staticcheck govulncheck go)
  tools=$(echo "$tools" | jq --argjson t "$go_tools" '.go = $t')
  if [[ "$go_count" -gt "$max_count" ]]; then max_count=$go_count; primary="go"; fi
fi

# C / C++
cpp_count=0
for ext in "*.c" "*.h" "*.cpp" "*.cxx" "*.cc" "*.hpp" "*.hxx"; do
  n=$(count_files "$ext")
  cpp_count=$((cpp_count + n))
done
if [[ "$cpp_count" -gt 0 ]]; then
  languages=$(echo "$languages" | jq --argjson c "$cpp_count" '.cpp = $c')
  cpp_tools=$(tools_json_array clang-tidy cppcheck)
  tools=$(echo "$tools" | jq --argjson t "$cpp_tools" '.cpp = $t')
  if [[ "$cpp_count" -gt "$max_count" ]]; then max_count=$cpp_count; primary="cpp"; fi
fi

# If no language reaches >=3 code files, treat as docs-only repo
if [[ "$max_count" -lt 3 ]]; then
  primary="docs"
fi

jq -n \
  --argjson langs "$languages" \
  --argjson tools "$tools" \
  --arg primary "$primary" \
  --arg root "$ROOT" \
  '{languages: $langs, tools: $tools, primary: $primary, root: $root}'
