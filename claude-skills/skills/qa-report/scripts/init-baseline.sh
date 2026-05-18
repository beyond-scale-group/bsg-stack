#!/usr/bin/env bash
# init-baseline.sh — generate a baseline QA snapshot from repo scan.
#
# Part of #237 (per-agent --init contract): scans the repo for test
# files, test frameworks, and CI coverage artifacts, then emits a
# draft QA baseline to stdout. The orchestrator (`/bsg-stack init`)
# captures stdout and writes it to `.bsg/reports/qa/baseline.md`, then
# opens a PR for human review. This script never writes to disk.
#
# Usage:
#   bash init-baseline.sh           # auto-scan current repo
#   bash init-baseline.sh --repo OWNER/NAME
#
# Exit 0 + content on stdout: success
# Exit 0 + minimal stub on stdout: no test signals found
# Exit 1: error (missing tool, no gh auth, etc.)

set -euo pipefail

REPO_FLAG=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_FLAG=(--repo "$2"); shift 2 ;;
    -h|--help) sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "init-baseline.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$REPO_ROOT"

today=$(date -u +%F)

repo_name="unknown"
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  repo_name=$(gh repo view "${REPO_FLAG[@]}" --json name --jq '.name' 2>/dev/null || echo "unknown")
fi
if [[ "$repo_name" == "unknown" || -z "$repo_name" ]]; then
  repo_name=$(basename "$REPO_ROOT")
fi

# ----------------------------------------------- signal collection

# Count test files by common naming conventions.
test_count=$(find . -type f \
  \( -name '*_test.go' -o -name '*.test.js' -o -name '*.test.ts' \
     -o -name '*.spec.js' -o -name '*.spec.ts' -o -name 'test_*.py' \
     -o -name '*_test.py' -o -name '*Test.java' -o -name '*_spec.rb' \) \
  -not -path './.git/*' -not -path './node_modules/*' 2>/dev/null | wc -l | tr -d ' ')

# Detect test framework / runner configuration.
declare -a frameworks
[[ -f jest.config.js || -f jest.config.ts ]] && frameworks+=("Jest")
grep -qs '"jest"' package.json 2>/dev/null && frameworks+=("Jest (package.json)")
[[ -f pytest.ini || -f tox.ini ]] && frameworks+=("pytest")
grep -qs '\[tool.pytest' pyproject.toml 2>/dev/null && frameworks+=("pytest (pyproject.toml)")
[[ -f vitest.config.ts || -f vitest.config.js ]] && frameworks+=("Vitest")
[[ -d spec ]] && frameworks+=("RSpec (spec/)")

# Coverage artifacts / config.
declare -a coverage
[[ -f lcov.info || -f coverage/lcov.info ]] && coverage+=("lcov.info")
[[ -f .coveragerc ]] && coverage+=(".coveragerc")
[[ -f coverage.xml ]] && coverage+=("coverage.xml")
[[ -d coverage ]] && coverage+=("coverage/ directory")
[[ -d htmlcov ]] && coverage+=("htmlcov/ directory")

# CI presence.
ci="none detected"
[[ -d .github/workflows ]] && ci="GitHub Actions (.github/workflows/)"

# ----------------------------------------------- emit

cat <<HEAD
# QA baseline — ${repo_name}

_Draft bootstrapped ${today}. This is a first-tick snapshot, not a
graded report. The qa agent reads this directory every tick and
appends dated audits alongside it (\`.bsg/reports/qa/YYYY-MM-DD-audit.md\`).
Use this baseline to track whether coverage and risk move in the right
direction over time._

## Test inventory

- **Test files detected:** ${test_count}
HEAD

if [[ ${#frameworks[@]} -gt 0 ]]; then
  printf -- '- **Frameworks / runners:** %s\n' "$(printf '%s, ' "${frameworks[@]}" | sed 's/, $//')"
else
  printf -- '- **Frameworks / runners:** _none detected — document the test setup manually._\n'
fi
echo "- **CI:** $ci"

printf '\n## Coverage artifacts\n\n'
if [[ ${#coverage[@]} -gt 0 ]]; then
  for c in "${coverage[@]}"; do echo "- \`$c\`"; done
else
  echo "- _No coverage artifacts found. Wire up coverage in CI so the qa agent can track trends._"
fi

cat <<'TAIL'

## Risk hotspots

_The qa agent fills this on each tick: high-churn + low-coverage files
ranked by regression risk. Leave it empty on first commit._

## Notes

_Anything a reviewer should know about the test strategy: known gaps,
deliberately untested areas, flaky suites to watch._
TAIL
