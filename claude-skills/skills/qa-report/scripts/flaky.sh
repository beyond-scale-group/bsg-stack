#!/usr/bin/env bash
# flaky.sh — detect flaky tests from recent CI runs.
#
# The true flake signal (pass-fail-pass on same SHA, or alternating
# pass/fail) requires parsing per-test results across runs, which varies
# by test framework and CI config. This MVP uses a coarser heuristic:
# identify workflow *names* whose recent runs have an ambiguous
# pass/fail pattern (pass rate between 0.2 and 0.8 over >= 5 runs).
# The agent narrates the findings and can drill into specific runs
# with `gh run view`.

set -euo pipefail

SNAPSHOT=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --snapshot) SNAPSHOT="$2"; shift 2 ;;
    *) shift ;;
  esac
done

if [[ -z "$SNAPSHOT" ]]; then
  SNAPSHOT=$(mktemp -t qa-snap.XXXXXX.json)
  trap 'rm -f "$SNAPSHOT"' EXIT
  SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
  bash "$SCRIPT_DIR/collect.sh" > "$SNAPSHOT"
fi

# Previous flakes (by workflow name) from the last archived snapshot's
# flaky output, so we can compute newFlakes[]. When there's no history
# yet, treat every detected flake as new.
PREV_DATE=""
PREV_FLAKES_JSON='[]'
HISTORY_DIR=$(jq -r '.repoRoot' "$SNAPSHOT")/qa/history
if [[ -d "$HISTORY_DIR" ]]; then
  prev=$(ls -t "$HISTORY_DIR"/*.json 2>/dev/null | head -1 || true)
  if [[ -n "$prev" ]]; then
    PREV_DATE=$(basename "$prev" .json)
    # If the snapshot carries embedded flake data from a previous tick,
    # fall back to an empty list (flake data lives in reports, not
    # snapshots, in this MVP).
    PREV_FLAKES_JSON=$(jq '.flakes // []' "$prev" 2>/dev/null || echo '[]')
  fi
fi

TODAY=$(date +%F)

jq --arg today "$TODAY" --argjson prevFlakes "$PREV_FLAKES_JSON" '
  (.ciRuns // []) as $runs
  | ($runs | length) as $n
  | if $n < 5 then
      {
        summary: { windowDays: .flakeWindowDays, runsAnalyzed: $n, flakeCount: 0, newFlakes: 0 },
        flakes: [],
        newFlakes: [],
        applicable: ($n > 0),
        reason: (if $n == 0 then "no CI runs available" else "not enough runs (< 5)" end)
      }
    else
      (
        $runs
        | group_by(.name)
        | map(
            {
              test: .[0].name,
              runs: length,
              passes:   ([.[] | select(.conclusion == "success")] | length),
              failures: ([.[] | select(.conclusion == "failure")] | length),
              lastFailedRun: ([.[] | select(.conclusion == "failure")] | sort_by(.createdAt) | last | .url // null),
              firstSeen: (map(.createdAt) | min | split("T")[0])
            }
            | .passRate = (if .runs == 0 then null else (.passes * 1.0 / .runs) end)
          )
        | map(select(.runs >= 5 and .passRate != null and .passRate > 0.2 and .passRate < 0.8))
      ) as $flakes
      | ($flakes | map(select(.test as $t | ($prevFlakes | map(.test) | index($t)) == null))) as $newFlakes
      | {
          summary: {
            windowDays: .flakeWindowDays,
            runsAnalyzed: $n,
            flakeCount: ($flakes | length),
            newFlakes: ($newFlakes | length)
          },
          flakes: $flakes,
          newFlakes: ($newFlakes | map(.firstSeen = $today))
        }
    end
' "$SNAPSHOT"
