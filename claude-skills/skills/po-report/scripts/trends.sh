#!/usr/bin/env bash
# trends.sh — velocity + scope-delta over time, from po/history/*.json.
#
# Reads every committed snapshot under po/history/ (oldest → newest)
# and emits a JSON timeseries. Because snapshots are committed every
# run, git history IS the trend store — no separate DB required.
#
# Output shape:
#   {
#     "series": [ { "date": "YYYY-MM-DD", "openIssues": N, "closedIssues": N,
#                   "openPrs": N, "mergedPrs": N, "milestones": [ {title, percentComplete, daysRemaining} ] } ],
#     "velocity": { "issuesClosedPerWeek": N.N, "prsMergedPerWeek": N.N,
#                   "samplePoints": N, "spanDays": N },
#     "latestChange": {
#       "newIssues": [...], "closedIssues": [...],
#       "newPrs": [...],    "mergedPrs": [...]
#     }
#   }
#
# If fewer than 2 history files exist, velocity is null and
# latestChange is empty — not an error.
#
# Usage:
#   bash trends.sh                    # reads ./po/history/*.json
#   bash trends.sh --dir ~/foo/po/history
set -euo pipefail

HISTORY_DIR="$PWD/po/history"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir) HISTORY_DIR="$2"; shift 2 ;;
    *) echo "trends.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done

# If the directory is missing or empty, emit a well-formed empty
# trends object so downstream reporting can say "no history yet".
if [[ ! -d "$HISTORY_DIR" ]]; then
  jq -n '{series: [], velocity: null, latestChange: null, historyDir: "'"$HISTORY_DIR"'"}'
  exit 0
fi

# Collect history files sorted by filename (date-based — lexicographic
# sort matches chronological order).
shopt -s nullglob
files=("$HISTORY_DIR"/*.json)
shopt -u nullglob

if [[ ${#files[@]} -eq 0 ]]; then
  jq -n '{series: [], velocity: null, latestChange: null, historyDir: "'"$HISTORY_DIR"'"}'
  exit 0
fi

# Sort by filename to get chronological order.
IFS=$'\n' sorted=($(printf '%s\n' "${files[@]}" | sort))
unset IFS

# Build one-line-per-snapshot JSON array with computed counts.
series=$(for f in "${sorted[@]}"; do
  jq -c '{
    date: (.generatedAt[:10] // (input_filename | capture("(?<d>\\d{4}-\\d{2}-\\d{2})").d)),
    openIssues:   ([.issues[] | select(.state == "OPEN")] | length),
    closedIssues: ([.issues[] | select(.state == "CLOSED")] | length),
    openPrs:      ([.pullRequests[] | select(.state == "OPEN")] | length),
    mergedPrs:    ([.pullRequests[] | select(.state == "MERGED")] | length),
    milestones:   ([.milestones[] | select(.state == "open") | {title, percentComplete: (.percentComplete // 0), daysRemaining: null}])
  }' "$f"
done | jq -s '.')

# Compute velocity from first vs last snapshot.
jq -n \
  --argjson series "$series" \
  --arg historyDir "$HISTORY_DIR" '
  ($series | length) as $n
  | if $n < 2 then
      {series: $series, velocity: null, latestChange: null, historyDir: $historyDir}
    else
      $series[0]  as $first
      | $series[-1] as $last
      | (
          (($last.date | strptime("%Y-%m-%d") | mktime) -
           ($first.date | strptime("%Y-%m-%d") | mktime)) / 86400
        ) as $spanDays
      | ($last.closedIssues - $first.closedIssues) as $closedDelta
      | ($last.mergedPrs    - $first.mergedPrs)    as $mergedDelta
      | {
          series: $series,
          velocity: (
            if $spanDays <= 0 then null
            else {
              issuesClosedPerWeek: (($closedDelta * 7 / $spanDays * 100 | floor) / 100),
              prsMergedPerWeek:    (($mergedDelta * 7 / $spanDays * 100 | floor) / 100),
              samplePoints: $n,
              spanDays: ($spanDays | floor)
            }
            end
          ),
          latestChange: {
            newIssuesSinceStart:  ($last.openIssues   - $first.openIssues),
            newPrsSinceStart:     ($last.openPrs      - $first.openPrs),
            closedSinceStart:     $closedDelta,
            mergedSinceStart:     $mergedDelta
          },
          historyDir: $historyDir
        }
    end
'
