#!/usr/bin/env bash
# init-qa.sh — generate a draft QA baseline snapshot from repo scan.
#
# Part of #237 (per-agent --init contract): detects the repo's test
# framework, coverage tooling, test file count, and CI test step, then
# emits a draft `baseline.md` to stdout. The qa agent reads
# `.bsg/reports/qa/` every tick; this seed gives a fresh repo a
# starting quality snapshot instead of an empty directory.
#
# The orchestrator (`/bsg-stack init`) captures stdout and writes it to
# `.bsg/reports/qa/baseline.md` — this script never writes to disk.
#
# Usage:
#   bash init-qa.sh
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

# ----------------------------------------------- signal collection

test_framework="none detected"
if [[ -f package.json ]]; then
  pkg=$(cat package.json 2>/dev/null || echo '{}')
  if   grep -q '"vitest"'  <<<"$pkg"; then test_framework="Vitest"
  elif grep -q '"jest"'    <<<"$pkg"; then test_framework="Jest"
  elif grep -q '"mocha"'   <<<"$pkg"; then test_framework="Mocha"
  elif grep -q '"playwright"' <<<"$pkg"; then test_framework="Playwright"
  fi
fi
if [[ "$test_framework" == "none detected" ]]; then
  if   [[ -f pytest.ini || -f conftest.py ]] || grep -rqs 'pytest' pyproject.toml setup.cfg 2>/dev/null; then
    test_framework="pytest"
  elif [[ -f go.mod ]] && find . -name '*_test.go' -not -path './.git/*' 2>/dev/null | grep -q .; then
    test_framework="go test"
  elif [[ -f Cargo.toml ]]; then
    test_framework="cargo test"
  fi
fi

coverage_tool="none detected"
if   [[ -f lcov.info ]] || find . -name 'lcov.info' -not -path './.git/*' 2>/dev/null | grep -q .; then
  coverage_tool="lcov (lcov.info present)"
elif [[ -f .coveragerc ]] || grep -rqs 'coverage' pyproject.toml setup.cfg 2>/dev/null; then
  coverage_tool="coverage.py"
elif [[ -f package.json ]] && grep -q '"nyc"\|"c8"\|"istanbul"' package.json 2>/dev/null; then
  coverage_tool="istanbul/nyc/c8"
fi

# Count test files across common conventions.
test_file_count=$(find . \
  \( -path ./.git -o -path ./node_modules -o -path ./.venv \) -prune -o \
  -type f \( -name '*.test.*' -o -name '*.spec.*' -o -name 'test_*.py' \
             -o -name '*_test.go' -o -name '*_test.py' \) -print 2>/dev/null \
  | wc -l | tr -d ' ')

ci_test_step="not detected"
if [[ -d .github/workflows ]]; then
  if grep -rqsE 'test|pytest|jest|vitest|coverage' .github/workflows/ 2>/dev/null; then
    ci_test_step="GitHub Actions workflow runs tests"
  else
    ci_test_step="GitHub Actions present, no obvious test step"
  fi
fi

repo_name=$(basename "$REPO_ROOT")
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  n=$(gh repo view --json name --jq '.name' 2>/dev/null || true)
  [[ -n "$n" ]] && repo_name="$n"
fi

# ----------------------------------------------- emit

cat <<DOC
# QA baseline — ${repo_name}

_Draft bootstrapped ${today}. Edit and commit to
\`.bsg/reports/qa/baseline.md\` — the qa agent reads this directory
every tick and compares new findings against this baseline. Treat the
numbers below as a starting point, not ground truth._

## Detected test setup

| Aspect | Detected value |
|---|---|
| Test framework | ${test_framework} |
| Coverage tool | ${coverage_tool} |
| Test files found | ${test_file_count} |
| CI test step | ${ci_test_step} |

## Risk hotspots

_The qa agent fills this section each tick with modules that have low
coverage, high churn, or recurring regressions. Leave it empty on the
first commit — it is populated from real audit data over time._

## Baseline notes

- If **test framework** is \`none detected\`, the qa agent's first
  recommendation will be to introduce a test harness.
- If **coverage tool** is \`none detected\`, add one so coverage deltas
  can be tracked tick over tick.
- Update this baseline deliberately (e.g. after a major coverage push)
  so regressions are measured against an intentional reference point.
DOC
