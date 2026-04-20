#!/usr/bin/env bash
# debt.sh — TODO/FIXME/HACK inventory with age-based scoring.

set -euo pipefail

SNAPSHOT=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --snapshot) SNAPSHOT="$2"; shift 2 ;;
    *) shift ;;
  esac
done

if [[ -z "$SNAPSHOT" ]]; then
  SNAPSHOT=$(mktemp -t tech-snap.XXXXXX.json)
  trap 'rm -f "$SNAPSHOT"' EXIT
  SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
  bash "$SCRIPT_DIR/collect.sh" > "$SNAPSHOT"
fi

jq '
  (.todos // []) as $todos
  | ($todos | group_by(.kind) | map({ (.[0].kind): length }) | add // {}) as $counts
  | ($todos
      | [ group_by(.file)[] | { file: .[0].file, count: length, oldest: (map(.date) | min) } ]
      | sort_by(-.count)
    ) as $byFile
  | [ $todos[] | select(.age > 90) ] as $stale
  | ($todos | map(
        (if   .kind == "TODO"  then 1
         elif .kind == "FIXME" then 2
         elif .kind == "HACK"  then 3
         else 1 end) as $w
        | (if   .age > 90 then 4
           elif .age > 30 then 2
           else 1 end) as $m
        | $w * $m
      ) | add // 0
    ) as $debtScore
  | (.previous // {} | .debtScore) as $prev
  |
  {
    summary: {
      todo:  ($counts.TODO // 0),
      fixme: ($counts.FIXME // 0),
      hack:  ($counts.HACK // 0),
      total: ($todos | length),
      oldestDate: ($todos | map(.date) | min)
    },
    byFile: $byFile,
    staleTodos: $stale,
    debtScore: $debtScore,
    previousDebtScore: $prev,
    debtScoreDelta: (if $prev == null then null else ($debtScore - $prev) end)
  }
' "$SNAPSHOT"
