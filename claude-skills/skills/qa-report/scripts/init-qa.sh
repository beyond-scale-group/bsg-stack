#!/usr/bin/env bash
# init-qa.sh — generate a draft QA baseline snapshot from repo scan.
#
# Part of #237 (per-agent --init contract): scans the repo for its
# test framework, test files, and coverage tooling, then emits a
# draft `.bsg/reports/qa/baseline.md` to stdout. The qa agent reads
# `.bsg/reports/qa/` every tick to track quality signals over time;
# this baseline gives the first tick something to diff against.
#
# The orchestrator (`/bsg-stack init`) captures stdout and writes it
# to `.bsg/reports/qa/baseline.md` for human review — this script
# never writes to disk.
#
# Usage:
#   bash init-qa.sh           # auto-scan current repo
#
# Exit 0 + content on stdout: success
# Exit 1: error

set -euo pipefail

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "init-qa.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$REPO_ROOT"

today=$(date -u +%F)

repo_name=$(basename "$REPO_ROOT")
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  repo_name=$(gh repo view --json name --jq '.name // empty' 2>/dev/null || echo "$repo_name")
fi

# Accumulate findings as newline-delimited text rather than bash arrays —
# referencing an empty array under `set -u` is an "unbound variable"
# error on bash < 4.4, which the orchestrator may run on.

# ----------------------------------------------- signals: test framework

frameworks=""
add_fw() {
  case $'\n'"$frameworks"$'\n' in
    *$'\n'"$1"$'\n'*) return ;;
  esac
  frameworks="${frameworks:+$frameworks$'\n'}$1"
}

if [[ -f package.json ]] && command -v jq >/dev/null 2>&1; then
  alldeps=$(jq -r '((.dependencies // {}) + (.devDependencies // {})) | keys[]' \
    package.json 2>/dev/null || echo "")
  grep -qx 'jest'       <<<"$alldeps" && add_fw "Jest"
  grep -qx 'vitest'     <<<"$alldeps" && add_fw "Vitest"
  grep -qx 'mocha'      <<<"$alldeps" && add_fw "Mocha"
  grep -qx 'playwright' <<<"$alldeps" && add_fw "Playwright"
  grep -qx 'cypress'    <<<"$alldeps" && add_fw "Cypress"
fi
{ [[ -f pytest.ini ]] || [[ -f tox.ini ]]; } && add_fw "pytest"
grep -rqs 'pytest' pyproject.toml setup.cfg 2>/dev/null && add_fw "pytest"
{ [[ -f build.sbt ]] && grep -rqs 'scoverage\|scalatest\|munit' build.sbt 2>/dev/null; } \
  && add_fw "Scala test (scalatest/munit)"
[[ -f go.mod ]]     && add_fw "Go testing (go test)"
[[ -f Cargo.toml ]] && add_fw "Rust test (cargo test)"

# ----------------------------------------------- signals: test files

test_count=$(find . -type f \
  -not -path './.git/*' -not -path './node_modules/*' \( \
    -name '*.test.*' -o -name '*.spec.*' \
    -o -name 'test_*.py' -o -name '*_test.py' \
    -o -name '*_test.go' -o -name '*Test.scala' -o -name '*Spec.scala' \
  \) 2>/dev/null | wc -l | tr -d ' ' || echo 0)
test_dirs=$(find . -maxdepth 4 -type d \
  -not -path './.git/*' -not -path './node_modules/*' \( \
    -name 'tests' -o -name 'test' -o -name '__tests__' -o -name 'spec' \
  \) 2>/dev/null | sed 's#^\./##' | sort -u | head -10 \
  | awk '{print "- " $0}' || echo "")

# ----------------------------------------------- signals: coverage

coverage=""
add_cov() {
  case $'\n'"$coverage"$'\n' in
    *$'\n'"$1"$'\n'*) return ;;
  esac
  coverage="${coverage:+$coverage$'\n'}$1"
}
{ [[ -f lcov.info ]] || [[ -f coverage/lcov.info ]]; } && add_cov "lcov.info present"
[[ -d coverage ]] && add_cov "coverage/ directory present"
[[ -f cobertura.xml ]] && add_cov "Cobertura report present"
cov_json=$(find . -maxdepth 3 -name 'coverage-final.json' \
  -not -path './node_modules/*' 2>/dev/null | head -1 || true)
[[ -n "$cov_json" ]] && add_cov "Jest coverage-final.json present"
scoverage_dir=$(find . -maxdepth 4 -type d -name 'scoverage-report' \
  2>/dev/null | head -1 || true)
[[ -n "$scoverage_dir" ]] && add_cov "scoverage report present"

# ----------------------------------------------- emit

cat <<HEAD
# QA baseline — ${repo_name}

_Draft bootstrapped ${today}. Edit and commit to
\`.bsg/reports/qa/baseline.md\`. The qa agent reads
\`.bsg/reports/qa/\` every tick and diffs new findings against this
snapshot, so an honest baseline keeps the noise down._

## Test framework

HEAD

if [[ -n "$frameworks" ]]; then
  printf '%s\n' "$frameworks" | sed 's/^/- /'
else
  echo "- _No test framework detected — note the intended framework here._"
fi

cat <<COUNTS

## Test surface

- Test files detected: **${test_count}**
COUNTS

if [[ -n "$test_dirs" ]]; then
  echo ""
  echo "Test directories:"
  echo ""
  printf '%s\n' "$test_dirs"
fi

cat <<'COV_HEADER'

## Coverage tooling

COV_HEADER

if [[ -n "$coverage" ]]; then
  printf '%s\n' "$coverage" | sed 's/^/- /'
else
  echo "- _No coverage artifacts detected. Wire up a coverage tool"
  echo "  (lcov, scoverage, Jest --coverage) so the qa agent can track"
  echo "  trends over time._"
fi

cat <<'TAIL'

## Risk hotspots

_Empty on first commit. The qa agent fills this section each tick with
modules that lack tests, recently changed code without coverage, and
flaky test signals. Add any known fragile areas manually so the agent
prioritizes them._
TAIL
