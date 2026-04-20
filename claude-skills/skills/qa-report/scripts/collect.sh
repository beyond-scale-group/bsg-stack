#!/usr/bin/env bash
# collect.sh — one snapshot for the qa-report skill.
#
# Auto-detects the coverage report, parses it into a normalized schema,
# computes per-file churn for the last 30 days, and fetches recent CI
# workflow runs for flake detection. Emits a single JSON document on
# stdout that every reporter consumes with `--snapshot <path>`.

set -euo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$REPO_ROOT"

WINDOW_DAYS=30
FLAKE_WINDOW_DAYS=14
FLAKE_MAX_RUNS=50

# ------------------------------------------------------- coverage detection

COVERAGE_FORMAT="none"
COVERAGE_FOUND="false"
COVERAGE_FILE=""

for candidate in \
  "coverage/coverage-summary.json:istanbul-json" \
  "coverage/coverage-final.json:istanbul-full" \
  "coverage/lcov.info:lcov" \
  "coverage.xml:cobertura" \
  ".coverage:python-coverage" \
  "coverage.out:go-coverage"; do
  path=${candidate%%:*}
  fmt=${candidate##*:}
  if [[ -f "$path" ]]; then
    COVERAGE_FILE="$path"
    COVERAGE_FORMAT="$fmt"
    COVERAGE_FOUND="true"
    break
  fi
done

# Scala scoverage — glob-based (only search if target/ exists).
if [[ "$COVERAGE_FOUND" == "false" && -d target ]]; then
  scoverage=$(find target -maxdepth 3 -name 'scoverage.xml' -type f 2>/dev/null | head -1 || true)
  if [[ -n "$scoverage" ]]; then
    COVERAGE_FILE="$scoverage"
    COVERAGE_FORMAT="scoverage"
    COVERAGE_FOUND="true"
  fi
fi

# --------------------------------------------- coverage -> normalized JSON

COVERAGE_JSON='{"found": false, "format": "none", "perFile": [], "overall": {"line": null, "branch": null, "zeroCoverage": null}}'

if [[ "$COVERAGE_FOUND" == "true" ]]; then
  case "$COVERAGE_FORMAT" in
    istanbul-json)
      # Istanbul coverage-summary.json: { "total": {...}, "/abs/path": {...} }
      COVERAGE_JSON=$(jq --arg fmt "$COVERAGE_FORMAT" --arg root "$REPO_ROOT/" '
        . as $s
        | ($s.total // {}) as $t
        | {
            found: true,
            format: $fmt,
            overall: {
              line: ($t.lines.pct // null),
              branch: ($t.branches.pct // null),
              zeroCoverage: ([to_entries[] | select(.key != "total") | select(.value.lines.pct == 0)] | length)
            },
            perFile: [
              to_entries[] | select(.key != "total")
              | { path: (.key | sub($root; "")),
                  linePct: (.value.lines.pct // 0),
                  branchPct: (.value.branches.pct // 0) }
            ]
          }
      ' "$COVERAGE_FILE" 2>/dev/null || echo "$COVERAGE_JSON")
      ;;
    lcov)
      # lcov.info — parse: SF:<file>, LF:<lines>, LH:<hit>, BRF:<branches>, BRH:<hit>
      COVERAGE_JSON=$(awk -v root="$REPO_ROOT/" '
        BEGIN { printf "["; first=1 }
        /^SF:/ {
          sub(/^SF:/, ""); file=$0;
          gsub(root, "", file);
          lf=0; lh=0; brf=0; brh=0
        }
        /^LF:/ { lf = substr($0, 4) }
        /^LH:/ { lh = substr($0, 4) }
        /^BRF:/ { brf = substr($0, 5) }
        /^BRH:/ { brh = substr($0, 5) }
        /^end_of_record/ {
          linePct = (lf > 0) ? (lh * 100.0 / lf) : 0
          branchPct = (brf > 0) ? (brh * 100.0 / brf) : 0
          if (!first) printf ","
          first=0
          printf "{\"path\":\"%s\",\"linePct\":%.2f,\"branchPct\":%.2f,\"linesTotal\":%d,\"linesHit\":%d}", file, linePct, branchPct, lf, lh
        }
        END { printf "]" }
      ' "$COVERAGE_FILE" 2>/dev/null | jq --arg fmt "$COVERAGE_FORMAT" '
        . as $files
        | {
            found: true,
            format: $fmt,
            overall: {
              line: (if ([.[].linesTotal] | add // 0) == 0 then null
                     else ([.[].linesHit] | add) * 100.0 / ([.[].linesTotal] | add) | . * 100 | floor / 100 end),
              branch: null,
              zeroCoverage: ([.[] | select(.linePct == 0)] | length)
            },
            perFile: [ .[] | { path, linePct, branchPct } ]
          }
      ' 2>/dev/null || echo "$COVERAGE_JSON")
      ;;
    cobertura|scoverage)
      # Cobertura: <coverage line-rate="0.72" branch-rate="0.58"> ... </coverage>
      # scoverage: <scoverage statement-count="..." statements-invoked="..." statement-rate="..."/>
      # Minimal parse — extract overall rates via grep.
      if [[ "$COVERAGE_FORMAT" == "cobertura" ]]; then
        line_rate=$(grep -oE 'line-rate="[0-9.]+"' "$COVERAGE_FILE" | head -1 | grep -oE '[0-9.]+' || echo "0")
        branch_rate=$(grep -oE 'branch-rate="[0-9.]+"' "$COVERAGE_FILE" | head -1 | grep -oE '[0-9.]+' || echo "0")
      else
        line_rate=$(grep -oE 'statement-rate="[0-9.]+"' "$COVERAGE_FILE" | head -1 | grep -oE '[0-9.]+' || echo "0")
        branch_rate="0"
      fi
      COVERAGE_JSON=$(jq -n --arg fmt "$COVERAGE_FORMAT" \
        --arg line "$line_rate" --arg branch "$branch_rate" '
        {
          found: true,
          format: $fmt,
          overall: {
            line: (($line | tonumber) * 100 | . * 100 | floor / 100),
            branch: (if $branch == "0" then null else (($branch | tonumber) * 100 | . * 100 | floor / 100) end),
            zeroCoverage: null
          },
          perFile: []
        }')
      ;;
    python-coverage|go-coverage|istanbul-full)
      # Formats we know about but don't fully parse yet — mark found, skip perFile.
      COVERAGE_JSON=$(jq -n --arg fmt "$COVERAGE_FORMAT" '
        { found: true, format: $fmt, overall: { line: null, branch: null, zeroCoverage: null }, perFile: [] }')
      ;;
  esac
fi

# -------------------------------------------------------------- churn

# Honor .qaignore (gitignore-style) by filtering after git emits the list.
QAIGNORE_PATTERNS=""
if [[ -f .qaignore ]]; then
  QAIGNORE_PATTERNS=$(grep -vE '^\s*(#|$)' .qaignore || true)
fi

CHURN_JSON=$(git log --no-merges --since="$WINDOW_DAYS days ago" --name-only --pretty=format: 2>/dev/null \
  | awk 'NF' \
  | grep -vE '(^|/)(package-lock\.json|yarn\.lock|pnpm-lock\.yaml|Cargo\.lock|poetry\.lock|Pipfile\.lock|go\.sum)$' \
  | sort | uniq -c | sort -rn \
  | awk '{count=$1; $1=""; sub(/^ /, ""); printf "{\"path\":\"%s\",\"commits\":%d}\n", $0, count}' \
  | jq -sc '.')

# ---------------------------------------------------------- CI runs

CI_RUNS_JSON='[]'
if command -v gh >/dev/null 2>&1; then
  CI_RUNS_JSON=$(gh run list \
    --limit "$FLAKE_MAX_RUNS" \
    --created ">=$(date -u -v-${FLAKE_WINDOW_DAYS}d +%F 2>/dev/null || date -u --date="${FLAKE_WINDOW_DAYS} days ago" +%F)" \
    --json databaseId,name,status,conclusion,headSha,createdAt,url \
    2>/dev/null || echo '[]')
fi

# --------------------------------------------- previous snapshot (trend)

PREVIOUS_JSON='null'
if [[ -d qa/history ]]; then
  prev=$(ls -t qa/history/*.json 2>/dev/null | head -1 || true)
  if [[ -n "$prev" ]]; then
    PREVIOUS_JSON=$(jq '{ date: (input_filename | split("/")[-1] | rtrimstr(".json")), coverage: .coverage }' "$prev" 2>/dev/null || echo 'null')
  fi
fi

# ------------------------------ test-suite detection (for silence-breaker)

TEST_SUITE_FOUND="false"
for candidate in "tests" "test" "__tests__" "spec"; do
  if [[ -d "$candidate" ]]; then
    TEST_SUITE_FOUND="true"; break
  fi
done
# Fallback: any *test*.* / *spec*.* under src/ or similar
if [[ "$TEST_SUITE_FOUND" == "false" ]]; then
  if git ls-files '*test*' '*spec*' 2>/dev/null | grep -qE '\.(ts|js|py|scala|go|rs|java)$'; then
    TEST_SUITE_FOUND="true"
  fi
fi

# ---------------------------------------------------------- emit

jq -n \
  --arg repoRoot "$REPO_ROOT" \
  --arg generatedAt "$(date -u +%FT%TZ)" \
  --argjson coverage "$COVERAGE_JSON" \
  --argjson churn "$CHURN_JSON" \
  --argjson ciRuns "$CI_RUNS_JSON" \
  --argjson previous "$PREVIOUS_JSON" \
  --arg testSuiteFound "$TEST_SUITE_FOUND" \
  --argjson windowDays "$WINDOW_DAYS" \
  --argjson flakeWindowDays "$FLAKE_WINDOW_DAYS" \
  '{
    repoRoot: $repoRoot,
    generatedAt: $generatedAt,
    windowDays: $windowDays,
    flakeWindowDays: $flakeWindowDays,
    coverage: $coverage,
    churn: $churn,
    ciRuns: $ciRuns,
    previous: $previous,
    testSuiteFound: ($testSuiteFound == "true")
  }'
