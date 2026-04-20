#!/usr/bin/env bash
# risk.sh — regression risk heatmap (churn × coverage).

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

jq '
  ( .coverage.perFile // [] ) as $cov
  | ( .churn // [] ) as $churn
  | ( [ $churn[] | { (.path): .commits } ] | add // {} ) as $churnMap
  | [
      $cov[] as $f
      | {
          path: $f.path,
          churn30d: ($churnMap[$f.path] // 0),
          coveragePct: ($f.linePct // 0),
          score: ( (($churnMap[$f.path] // 0) | tonumber)
                   * (1 - ($f.linePct // 0) / 100) | . * 100 | floor / 100 )
        }
      | .band = (
          if .churn30d >= 10 and .coveragePct < 10 then "critical"
          elif (.churn30d >= 10 and .coveragePct < 50) or (.churn30d >= 20) then "high"
          elif .churn30d >= 5 and .coveragePct < 50 then "moderate"
          else "low" end
        )
    ]
  | sort_by(-.score) as $ranked
  | {
      summary: {
        analyzedFiles: ($ranked | length),
        criticalCount: ([$ranked[] | select(.band == "critical")] | length),
        highCount:     ([$ranked[] | select(.band == "high")]     | length),
        moderateCount: ([$ranked[] | select(.band == "moderate")] | length)
      },
      criticalFiles: [$ranked[] | select(.band == "critical")],
      highRiskFiles: [$ranked[] | select(.band == "high")],
      moderateFiles: [$ranked[] | select(.band == "moderate")]
    }
' "$SNAPSHOT"
