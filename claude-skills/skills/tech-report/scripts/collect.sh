#!/usr/bin/env bash
# collect.sh — snapshot for the tech-report skill.
#
# Inventories: detected ecosystems, `npm outdated` / `pip list
# --outdated` output, recent Dependabot alerts, source file sizes,
# TODO/FIXME/HACK matches with blame dates, ADR directory + files,
# recent top-level dependency additions for the ADR gap detector.

set -euo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$REPO_ROOT"

# -------------------------------------------------------------- ecosystems

ECOSYSTEMS=()
[[ -f package-lock.json || -f yarn.lock || -f pnpm-lock.yaml || -f package.json ]] && ECOSYSTEMS+=("npm")
[[ -f Pipfile.lock || -f poetry.lock || -f requirements.txt ]] && ECOSYSTEMS+=("pip")

NPM_OUTDATED='{}'
if [[ " ${ECOSYSTEMS[*]} " == *" npm "* ]] && command -v npm >/dev/null 2>&1; then
  # `npm outdated --json` exits non-zero when there are outdated packages.
  NPM_OUTDATED=$(npm outdated --json 2>/dev/null || true)
  [[ -z "$NPM_OUTDATED" ]] && NPM_OUTDATED='{}'
fi

PIP_OUTDATED='[]'
if [[ " ${ECOSYSTEMS[*]} " == *" pip "* ]] && command -v pip >/dev/null 2>&1; then
  PIP_OUTDATED=$(pip list --outdated --format=json 2>/dev/null || echo '[]')
fi

# --------------------------------------------------------- gh dependabot

GHSA_JSON='[]'
if command -v gh >/dev/null 2>&1; then
  GHSA_JSON=$(gh api /repos/{owner}/{repo}/dependabot/alerts --paginate 2>/dev/null || echo '[]')
fi

# ------------------------------------------------------- source files

# Collect per-file line counts for tracked source files.
SOURCE_EXTS_REGEX='\.(ts|tsx|js|jsx|mjs|cjs|py|go|rs|scala|java|kt|rb|php|c|h|cpp|hpp)$'

SOURCE_FILES_JSON=$(git ls-files 2>/dev/null \
  | grep -E "$SOURCE_EXTS_REGEX" \
  | while IFS= read -r f; do
      [[ -f "$f" ]] || continue
      lines=$(wc -l < "$f" 2>/dev/null | tr -d ' ')
      printf '{"path":"%s","lines":%s}\n' "$f" "${lines:-0}"
    done \
  | jq -sc '.' 2>/dev/null || echo '[]')

# --------------------------------------------------------- TODO / FIXME

# Emit { file, line, kind, text, age_days } entries.
TODAY_EPOCH=$(date +%s)

TODOS_JSON=$({ git grep -n -E '(TODO|FIXME|HACK)[:(]' -- '*.ts' '*.tsx' '*.js' '*.jsx' '*.mjs' '*.cjs' '*.py' '*.go' '*.rs' '*.scala' '*.java' '*.kt' '*.rb' '*.md' 2>/dev/null || true; } \
  | while IFS=: read -r file line rest; do
      [[ -z "$file" || -z "$line" ]] && continue
      kind=$(echo "$rest" | grep -oE '(TODO|FIXME|HACK)' | head -1)
      text=$(echo "$rest" | sed -E "s/.*($kind)[:(]?//" | sed -E 's/^[[:space:]]+//' | cut -c1-120)
      blame_ts=$(git blame --porcelain -L "$line,$line" "$file" 2>/dev/null \
        | awk '/^committer-time / {print $2}' | head -1)
      if [[ -n "$blame_ts" ]]; then
        age_days=$(( (TODAY_EPOCH - blame_ts) / 86400 ))
        blame_date=$(date -r "$blame_ts" +%F 2>/dev/null || echo "unknown")
      else
        age_days=0
        blame_date="unknown"
      fi
      jq -nc --arg file "$file" --arg line "$line" --arg kind "$kind" --arg text "$text" --arg date "$blame_date" --arg age "$age_days" \
        '{file: $file, line: ($line | tonumber), kind: $kind, text: $text, date: $date, age: ($age | tonumber)}'
    done \
  | jq -sc '.' 2>/dev/null || echo '[]')

# -------------------------------------------------------------- ADRs

ADR_DIR=""
for candidate in "adr" "docs/adr" "architecture" "docs/architecture"; do
  if [[ -d "$candidate" ]]; then
    ADR_DIR="$candidate"; break
  fi
done

ADRS_JSON='[]'
if [[ -n "$ADR_DIR" ]]; then
  ADRS_JSON=$(find "$ADR_DIR" -type f -name '*.md' 2>/dev/null | while IFS= read -r f; do
    title=$(grep -m1 '^# ' "$f" 2>/dev/null | sed 's/^#[[:space:]]*//' || echo "?")
    id=$(basename "$f" | grep -oE '^[0-9]+' || echo "?")
    status=$(grep -m1 -iE '^status[[:space:]]*:' "$f" 2>/dev/null | sed -E 's/.*:[[:space:]]*//' | tr -d '\r' || echo "unknown")
    date=$(grep -m1 -iE '^date[[:space:]]*:' "$f" 2>/dev/null | sed -E 's/.*:[[:space:]]*//' | tr -d '\r' || echo "")
    jq -nc --arg id "$id" --arg title "$title" --arg status "$status" --arg date "$date" --arg path "$f" \
      '{id: $id, title: $title, status: $status, date: $date, path: $path}'
  done | jq -sc '.' 2>/dev/null || echo '[]')
fi

# ---------------------------------------------- recent new deps (30d window)

# Extract top-level package.json dependencies added in the last 30 days.
# Diff the current names against the names as of 30 days ago.
NEW_DEPS_JSON='[]'
if [[ -f package.json ]]; then
  current_names=$(jq -r '(.dependencies // {}) + (.devDependencies // {}) | keys[]' package.json 2>/dev/null | sort -u)
  old_ref=$(git rev-list -1 --before="30 days ago" main 2>/dev/null || git rev-list -1 --before="30 days ago" HEAD 2>/dev/null || true)
  if [[ -n "$old_ref" ]]; then
    old_names=$(git show "$old_ref:package.json" 2>/dev/null | jq -r '(.dependencies // {}) + (.devDependencies // {}) | keys[]' 2>/dev/null | sort -u)
    added=$(comm -23 <(echo "$current_names") <(echo "$old_names") | grep -v '^$' || true)
    if [[ -n "$added" ]]; then
      NEW_DEPS_JSON=$(echo "$added" | while IFS= read -r name; do
        jq -nc --arg name "$name" --arg eco "npm" '{dependency: $name, ecosystem: $eco}'
      done | jq -sc '.' 2>/dev/null || echo '[]')
    fi
  fi
fi

# --------------------------------------------- previous snapshot (trend)

PREVIOUS_JSON='null'
if [[ -d tech/history ]]; then
  prev=$(ls -t tech/history/*.json 2>/dev/null | head -1 || true)
  if [[ -n "$prev" ]]; then
    PREVIOUS_JSON=$(jq '{ date: (input_filename | split("/")[-1] | rtrimstr(".json")), debtScore: .debtScore }' "$prev" 2>/dev/null || echo 'null')
  fi
fi

# ---------------------------------------------------------- emit

jq -n \
  --arg repoRoot "$REPO_ROOT" \
  --arg generatedAt "$(date -u +%FT%TZ)" \
  --argjson ecosystems "$(printf '%s\n' "${ECOSYSTEMS[@]:-}" | jq -Rn '[inputs | select(length>0)]')" \
  --argjson npmOutdated "$NPM_OUTDATED" \
  --argjson pipOutdated "$PIP_OUTDATED" \
  --argjson dependabot "$GHSA_JSON" \
  --argjson sourceFiles "$SOURCE_FILES_JSON" \
  --argjson todos "$TODOS_JSON" \
  --arg adrDir "$ADR_DIR" \
  --argjson adrs "$ADRS_JSON" \
  --argjson newDeps "$NEW_DEPS_JSON" \
  --argjson previous "$PREVIOUS_JSON" \
  '{
    repoRoot: $repoRoot,
    generatedAt: $generatedAt,
    ecosystems: $ecosystems,
    deps: {
      npmOutdated: $npmOutdated,
      pipOutdated: $pipOutdated,
      dependabotAlerts: $dependabot
    },
    sourceFiles: $sourceFiles,
    todos: $todos,
    adr: {
      dir: (if $adrDir == "" then null else $adrDir end),
      entries: $adrs
    },
    newDeps: $newDeps,
    previous: $previous
  }'
