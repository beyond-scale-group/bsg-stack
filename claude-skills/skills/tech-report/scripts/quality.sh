#!/usr/bin/env bash
# quality.sh — file-size / function-count / circular-import heuristics.

set -euo pipefail

SNAPSHOT=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --snapshot) SNAPSHOT="$2"; shift 2 ;;
    *) shift ;;
  esac
done

if [[ -z "$SNAPSHOT" ]]; then
  SNAPSHOT=$(mktemp -t tech-snap.XXXXXX.json)
  trap 'rm -f "$SNAPSHOT"' EXIT
  SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
  bash "$SCRIPT_DIR/collect.sh" > "$SNAPSHOT"
fi

REPO_ROOT=$(jq -r '.repoRoot' "$SNAPSHOT")
cd "$REPO_ROOT"

MAX_LINES=500
MAX_FUNCTIONS=20

# Function-detection patterns per extension.
count_functions() {
  local f=$1
  case "$f" in
    *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs)
      grep -cE '^\s*(export\s+)?(async\s+)?function\s+\w+|^\s*(export\s+)?const\s+\w+\s*=\s*(async\s+)?\(' "$f" 2>/dev/null || echo 0 ;;
    *.py)
      grep -cE '^\s*(async\s+)?def\s+\w+' "$f" 2>/dev/null || echo 0 ;;
    *.go)
      grep -cE '^func\s+(\([^)]+\)\s+)?\w+' "$f" 2>/dev/null || echo 0 ;;
    *.rs)
      grep -cE '^\s*(pub(\([^)]+\))?\s+)?(async\s+)?fn\s+\w+' "$f" 2>/dev/null || echo 0 ;;
    *.scala)
      grep -cE '^\s*(private\s+|protected\s+)?def\s+\w+' "$f" 2>/dev/null || echo 0 ;;
    *) echo 0 ;;
  esac
}

# Compute per-file function counts and build oversized[] / dense[] lists.
OVERSIZED_JSON="[]"
DENSE_JSON="[]"

while IFS= read -r entry; do
  [[ -z "$entry" ]] && continue
  path=$(jq -r '.path' <<<"$entry")
  lines=$(jq -r '.lines' <<<"$entry")
  [[ -f "$path" ]] || continue
  functions=$(count_functions "$path")

  if (( lines > MAX_LINES )); then
    OVERSIZED_JSON=$(jq --arg p "$path" --argjson ln "$lines" --argjson fn "$functions" \
      '. + [{file: $p, lines: $ln, functions: $fn}]' <<<"$OVERSIZED_JSON")
  fi
  if (( functions > MAX_FUNCTIONS )); then
    DENSE_JSON=$(jq --arg p "$path" --argjson ln "$lines" --argjson fn "$functions" \
      '. + [{file: $p, lines: $ln, functions: $fn}]' <<<"$DENSE_JSON")
  fi
done < <(jq -c '.sourceFiles[]' "$SNAPSHOT")

# ---------------------------------------------------- circular imports (JS/TS only)

CIRCULAR_JSON='[]'
# Build import map: <from> -> [to, to, ...]
if jq -e '[.sourceFiles[] | select(.path | test("\\.(ts|tsx|js|jsx|mjs|cjs)$"))] | length > 0' "$SNAPSHOT" >/dev/null; then
  GRAPH_TMP=$(mktemp)
  while IFS= read -r f; do
    [[ -f "$f" ]] || continue
    grep -oE "(from|require\()\s*['\"][^'\"]+['\"]" "$f" 2>/dev/null \
      | grep -oE "['\"][^'\"]+['\"]" | tr -d '"'"'" \
      | grep -E '^\./|^\.\./' | while IFS= read -r imp; do
          dir=$(dirname "$f")
          # Resolve relative import to a path. Try common extensions.
          resolved=""
          for ext in ".ts" ".tsx" ".js" ".jsx" ".mjs" "/index.ts" "/index.js" ""; do
            candidate="$dir/$imp$ext"
            if [[ -f "$candidate" ]]; then
              resolved=$(realpath --relative-to="$REPO_ROOT" "$candidate" 2>/dev/null || echo "")
              break
            fi
          done
          if [[ -n "$resolved" ]]; then
            printf '%s\t%s\n' "$f" "$resolved"
          fi
        done
  done < <(jq -r '.sourceFiles[] | select(.path | test("\\.(ts|tsx|js|jsx|mjs|cjs)$")) | .path' "$SNAPSHOT") > "$GRAPH_TMP" || true

  # Detect trivial 2-cycles (A imports B, B imports A).
  CIRCULAR_JSON=$(awk -F'\t' '
    NR==FNR { fwd[$1][$2]=1; next }
    { if ($2 in fwd && $1 in fwd[$2]) {
        a=$1; b=$2;
        key = (a < b) ? (a "\t" b) : (b "\t" a);
        seen[key]=1
      } }
    END { for (k in seen) { split(k, p, "\t"); printf "{\"a\":\"%s\",\"b\":\"%s\"}\n", p[1], p[2] } }
  ' "$GRAPH_TMP" "$GRAPH_TMP" | jq -sc '.' 2>/dev/null || echo '[]')

  rm -f "$GRAPH_TMP"
fi

jq -n \
  --argjson over "$OVERSIZED_JSON" \
  --argjson dense "$DENSE_JSON" \
  --argjson circular "$CIRCULAR_JSON" \
  --argjson analyzed "$(jq '.sourceFiles | length' "$SNAPSHOT")" \
  '{
    summary: {
      filesAnalyzed: $analyzed,
      oversized: ($over | length),
      functionDense: ($dense | length),
      circularDeps: ($circular | length)
    },
    oversizedFiles: $over,
    functionDenseFiles: $dense,
    circularDeps: $circular
  }'
