#!/usr/bin/env bash
# init-qa-baseline.sh — generate a draft QA baseline from repo scan.
#
# Part of #237 (per-agent --init contract): scans the repo for
# existing test files and CI coverage artifacts, then emits a draft
# QA baseline snapshot to stdout (destined for
# `.bsg/reports/qa/<date>-baseline.md`). The orchestrator
# (`/bsg-stack init`) captures stdout and opens a PR for human
# review — this script never writes to disk.
#
# Usage:
#   bash init-qa-baseline.sh            # auto-scan current repo
#   bash init-qa-baseline.sh --repo OWNER/NAME
#
# Exit 0 + content on stdout: success
# Exit 1: error (missing tool, etc.)

set -euo pipefail

REPO_FLAG=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_FLAG=(--repo "$2"); shift 2 ;;
    -h|--help) sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "init-qa-baseline.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$REPO_ROOT"

today=$(date -u +%F)

repo_name="unknown"
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  repo_name=$(gh repo view "${REPO_FLAG[@]}" --json name -q '.name' 2>/dev/null || echo unknown)
fi

# ----------------------------------------------- signal collection

# Count test files by common naming conventions, skipping vendor dirs.
test_count=$(find . \
  -path ./.git -prune -o \
  -path ./node_modules -prune -o \
  -path ./.venv -prune -o \
  -path ./vendor -prune -o \
  -type f \( \
       -name '*_test.go' \
    -o -name 'test_*.py' \
    -o -name '*_test.py' \
    -o -name '*.test.js' \
    -o -name '*.test.ts' \
    -o -name '*.spec.js' \
    -o -name '*.spec.ts' \
    -o -name '*Test.java' \
  \) -print 2>/dev/null | wc -l | tr -d ' ')

# Detect dedicated test directories.
test_dirs=()
for d in test tests spec __tests__ src/test; do
  [[ -d "$d" ]] && test_dirs+=("$d/")
done

# Coverage artifacts already present in the repo.
coverage_artifacts=()
for f in lcov.info coverage.xml coverage/lcov.info .coverage \
         coverage-final.json clover.xml; do
  [[ -e "$f" ]] && coverage_artifacts+=("$f")
done

# CI test wiring (best-effort grep).
ci_tests="no test step detected"
if [[ -d .github/workflows ]]; then
  if grep -rqiE 'test|pytest|jest|vitest|go test' .github/workflows 2>/dev/null; then
    ci_tests="GitHub Actions references a test step"
  else
    ci_tests="GitHub Actions present, no obvious test step"
  fi
fi

# ----------------------------------------------- emit

cat <<HEAD
# QA baseline — ${repo_name}

_Draft bootstrapped ${today}. Review and commit to
\`.bsg/reports/qa/${today}-baseline.md\` — the qa agent uses this as
the starting point for tracking coverage and risk drift over time._

## Test inventory

HEAD

echo "- Test files detected: **${test_count}**"

if [[ ${#test_dirs[@]} -gt 0 ]]; then
  echo "- Test directories:"
  for d in "${test_dirs[@]}"; do echo "  - \`${d}\`"; done
else
  echo "- Test directories: _none found — no dedicated test tree detected._"
fi

echo ""
echo "## Coverage artifacts"
echo ""
if [[ ${#coverage_artifacts[@]} -gt 0 ]]; then
  for f in "${coverage_artifacts[@]}"; do echo "- \`${f}\` present"; done
else
  echo "- _No coverage artifact found — wire coverage reporting in CI so"
  echo "  the qa agent can track the trend._"
fi

echo ""
echo "## CI integration"
echo ""
echo "- ${ci_tests}"

cat <<'TAIL'

## Risk hotspots

_Seed this list with the modules that are most fragile or least
covered. The qa agent will keep it current on each tick — leave it
empty on first commit if you have no prior signal._

## Notes

_Adjust the inventory above if the heuristic missed a non-standard
test layout (the scan only knows common naming conventions)._
TAIL
