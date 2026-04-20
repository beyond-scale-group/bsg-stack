#!/usr/bin/env bash
# milestone-progress.sh — per-milestone progress with risk flags, as JSON.
#
# Reads a collect.sh snapshot via `--snapshot <path>`, stdin, or auto-run.
# Risk flags (at_risk, overdue, understaffed, stalled) are computed in
# jq from the snapshot — no extra API calls. Definitions match the
# table in `references/milestones.md`.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"

snapshot=""
if [[ ${1:-} == "--snapshot" ]]; then
  snapshot=$(cat "$2"); shift 2
elif [[ ! -t 0 ]]; then
  snapshot=$(cat)
fi
if [[ -z "$snapshot" ]]; then
  snapshot=$(bash "$HERE/collect.sh")
fi

printf '%s' "$snapshot" | jq '
  . as $root
  | (now) as $now
  | .milestones
  | map(select(.state == "open"))
  | map(
      . as $m
      | ($root.issues | map(select(.milestone != null and .milestone.title == $m.title))) as $issues
      | ([$issues[] | select(.state == "OPEN")]) as $open_issues
      | ($open_issues | length) as $open_count
      | ([$open_issues[] | select((.assignees | length) == 0)] | length) as $unassigned
      | ([$issues[] | select(.state == "CLOSED" and .closedAt != null) | .closedAt | fromdateiso8601] | max) as $lastClose
      | (if $lastClose then (($now - $lastClose) / 86400 | floor) else null end) as $daysSinceLastClose
      | ($m.dueOn | if . then fromdateiso8601 else null end) as $dueTs
      | (if $dueTs then (($dueTs - $now) / 86400 | floor) else null end) as $daysRemaining
      | $m + {
          daysRemaining: $daysRemaining,
          daysSinceLastClose: $daysSinceLastClose,
          flags: {
            overdue:      ($dueTs != null and $dueTs < $now and ($m.openIssues // 0) > 0),
            at_risk:      ($daysRemaining != null and $daysRemaining >= 0 and $daysRemaining <= 7 and ($m.percentComplete // 0) < 50),
            understaffed: ($open_count > 5 and (($unassigned * 2) > $open_count)),
            stalled:      ($open_count > 0 and (($daysSinceLastClose // 99999) > 7))
          }
        }
    )
'
