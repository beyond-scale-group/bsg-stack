#!/usr/bin/env bash
# init-qa-baseline.sh — generate a draft QA baseline from repo scan.
#
# Part of #237 (per-agent --init contract): scans the repo for test
# files and CI coverage artifacts and emits a draft baseline QA
# snapshot to stdout. The qa agent reads `.bsg/reports/qa/` every
# tick to track coverage trends and regression risk against a known
# starting point.
#
# The orchestrator (`/bsg-stack init`) captures stdout and writes it
# to `.bsg/reports/qa/0000-baseline.md`, then opens a PR for human
# review — this script never writes to disk.
#
# Usage:
#   bash init-qa-baseline.sh
#
# Exit 0 + content on stdout: success
# Exit 2: bad arguments

set -euo pipefail

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "init-qa-baseline.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$REPO_ROOT"

today=$(date -u +%F)

# ----------------------------------------------- signals

# 1. Test files — count by common naming conventions, skipping vendored
#    trees so the number reflects first-party tests.
test_count=$(find . -type f \
  -not -path './.git/*' -not -path './node_modules/*' \
  -not -path './vendor/*' -not -path './.venv/*' \( \
    -name '*_test.go' -o -name 'test_*.py' -o -name '*_test.py' \
    -o -name '*.test.js' -o -name '*.test.ts' -o -name '*.test.jsx' \
    -o -name '*.test.tsx' -o -name '*.spec.js' -o -name '*.spec.ts' \
    -o -name '*Test.java' -o -name '*_spec.rb' \
  \) 2>/dev/null | wc -l | tr -d ' ')

# Top-level directories that look like test roots.
test_dirs=$(find . -maxdepth 2 -type d \
  -not -path './.git/*' -not -path './node_modules/*' \( \
    -name 'tests' -o -name 'test' -o -name '__tests__' -o -name 'spec' \
  \) 2>/dev/null | sed 's|^\./||' | sort -u | head -10 \
  | awk 'NR>1{printf ", "}{printf "%s",$0}END{if(NR)print ""}')

# 2. CI coverage artifacts — the qa agent parses these every tick.
COVERAGE=()
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  COVERAGE+=("${f#./}")
done < <(find . -maxdepth 3 -type f \
  -not -path './.git/*' -not -path './node_modules/*' \( \
    -name 'lcov.info' -o -name 'coverage-summary.json' \
    -o -name 'coverage.xml' -o -name 'cobertura.xml' -o -name '.coverage' \
  \) 2>/dev/null | head -10)

# 3. CI setup that would produce those artifacts.
ci_setup="_None detected — wire coverage upload in CI so the qa agent has a trend to track._"
if [[ -d .github/workflows ]]; then
  wf_count=$(find .github/workflows -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' \) 2>/dev/null | wc -l | tr -d ' ')
  ci_setup="GitHub Actions — ${wf_count} workflow file(s) under \`.github/workflows/\`."
elif [[ -f .gitlab-ci.yml ]]; then
  ci_setup="GitLab CI (\`.gitlab-ci.yml\`)."
fi

# ----------------------------------------------- emit

cat <<HEAD
# QA baseline — bootstrapped ${today}

_This snapshot was bootstrapped automatically from a repo scan. It is
the **starting point** the qa agent measures future coverage and
regression-risk trends against — review the numbers, correct anything
the scan got wrong, and commit it to \`.bsg/reports/qa/0000-baseline.md\`._

## Test inventory

- **First-party test files detected:** ${test_count}
- **Test roots:** ${test_dirs:-_none detected — add a tests/ tree or set this manually._}

## Coverage artifacts

HEAD

if [[ "${#COVERAGE[@]}" -eq 0 ]]; then
  cat <<'EMPTY'
_No coverage artifact found in the working tree._

The qa agent reads one of `lcov.info`, `coverage-summary.json`,
`coverage.xml`, `cobertura.xml`, or `.coverage` to compute coverage
deltas. Generate one in CI (and, ideally, commit a copy or upload it
as an artifact) so the agent has a trend to track from this baseline.
EMPTY
else
  echo "Detected — the qa agent will parse these on each tick:"
  echo ""
  printf -- '- `%s`\n' "${COVERAGE[@]}"
fi

cat <<TAIL

## CI

${ci_setup}

## Baseline metrics

_Fill these in from the first real audit so future ticks have a
reference point. Leave \`—\` until measured._

| Metric                  | Baseline |
|-------------------------|----------|
| Line coverage           | —        |
| Branch coverage         | —        |
| High-risk files (churn × low coverage) | — |
| Known flaky tests       | —        |

## Notes

_Replace this section with anything a reviewer should know about the
current test posture — known gaps, untested critical paths, modules
deliberately excluded from coverage._
TAIL
