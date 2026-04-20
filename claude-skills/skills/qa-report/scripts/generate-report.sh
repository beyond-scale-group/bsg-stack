#!/usr/bin/env bash
# generate-report.sh — compose a full QA audit report.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

SNAPSHOT=$(mktemp -t qa-snap.XXXXXX.json)
trap 'rm -f "$SNAPSHOT"' EXIT

bash "$SCRIPT_DIR/collect.sh" > "$SNAPSHOT"

COVERAGE=$(bash "$SCRIPT_DIR/coverage.sh" --snapshot "$SNAPSHOT")
RISK=$(bash "$SCRIPT_DIR/risk.sh"         --snapshot "$SNAPSHOT")
FLAKY=$(bash "$SCRIPT_DIR/flaky.sh"       --snapshot "$SNAPSHOT")

DATE=$(date +%F)
REPO=$(jq -r '.repoRoot' "$SNAPSHOT" | xargs -I{} basename {})
TEST_SUITE_FOUND=$(jq -r '.testSuiteFound' "$SNAPSHOT")

cat <<EOF
# QA Audit — $DATE

**Repository:** \`$REPO\`
**Generated:** $(jq -r '.generatedAt' "$SNAPSHOT")
**Test suite present:** $TEST_SUITE_FOUND

---

## Coverage Summary

$(jq -r '
  if .found == false then
    "_No coverage report found. Configure your CI to emit lcov.info, coverage-summary.json, coverage.xml, .coverage, or coverage.out at the repo root._"
  else
    "Format: \u0060\(.format)\u0060\n\n" +
    "| Metric | Current | Previous | Delta |\n" +
    "|--------|---------|----------|-------|\n" +
    "| Line coverage   | \((.current.line.pct // "n/a"))%   | \((.previous.line.pct // "n/a"))%   | \((.delta.line // "n/a"))% |\n" +
    "| Branch coverage | \((.current.branch.pct // "n/a"))% | \((.previous.branch.pct // "n/a"))% | \((.delta.branch // "n/a"))% |\n" +
    "| Files with 0%   | \(.current.files.zeroCoverage // "n/a") | \((.previous.files.zeroCoverage // "n/a")) | \((.delta.zeroCoverage // "n/a")) |"
  end
' <<<"$COVERAGE")

---

## Regression Risk Heatmap

$(jq -r '
  .summary as $s
  | "**Summary:** \($s.analyzedFiles) files analyzed — \($s.criticalCount) critical, \($s.highCount) high, \($s.moderateCount) moderate"
' <<<"$RISK")

$(jq -r '
  if (.criticalFiles | length) == 0 and (.highRiskFiles | length) == 0 then
    "_No high-risk files detected._"
  else
    (
      "| File | Commits (30d) | Coverage | Score | Band |",
      "|------|---------------|----------|-------|------|",
      (.criticalFiles[] | "| \(.path) | \(.churn30d) | \(.coveragePct)% | \(.score) | **CRITICAL** |"),
      (.highRiskFiles[] | "| \(.path) | \(.churn30d) | \(.coveragePct)% | \(.score) | HIGH |")
    )
  end
' <<<"$RISK")

---

## Flaky Tests (last 14 days)

$(jq -r '
  if (.applicable // true) == false then
    "_\(.reason // "Flaky detection not applicable").\n_"
  else
    "**Summary:** \(.summary.runsAnalyzed) CI runs analyzed, \(.summary.flakeCount) flake(s) detected (\(.summary.newFlakes) new)"
  end
' <<<"$FLAKY")

$(jq -r '
  if (.applicable // true) == false or (.flakes | length) == 0 then
    "\n_No flaky tests detected in the window._"
  else
    (
      "| Workflow | Pass rate | Runs | First seen | Last failing run |",
      "|----------|-----------|------|------------|------------------|",
      (.flakes[] | "| \(.test) | \((.passRate * 100 | floor))% | \(.runs) | \(.firstSeen) | \(.lastFailedRun // "-") |")
    )
  end
' <<<"$FLAKY")

---

## Untested Areas

$(jq -r '
  [.criticalFiles[], .highRiskFiles[]] as $risky
  | if ($risky | length) == 0 then "_No notable untested areas flagged._"
    else
      "The following paths combine non-trivial churn with low coverage:\n\n" +
      ([$risky[] | "- \u0060\(.path)\u0060 — \(.churn30d) commits in 30d, \(.coveragePct)% coverage"] | join("\n"))
    end
' <<<"$RISK")

EOF
