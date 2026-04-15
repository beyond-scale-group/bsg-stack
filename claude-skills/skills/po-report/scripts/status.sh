#!/usr/bin/env bash
# status.sh — repo-wide PO counts and PR flow metrics, as JSON.
#
# Reads a collect.sh snapshot (one paginated GraphQL fetch per run) via
# `--snapshot <path>`, stdin, or auto-runs collect.sh if invoked with
# no input. No direct `gh` calls here — every number is a jq transform
# of the snapshot, so the same numbers can be re-derived from a past
# `po/history/<date>.json` without any GitHub traffic.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"

snapshot=""
if [[ ${1:-} == "--snapshot" ]]; then
  snapshot=$(cat "$2"); shift 2
elif [[ ! -t 0 ]]; then
  snapshot=$(cat)
fi
# Fall back to a fresh collection when no usable input was supplied —
# covers TTY runs and subprocess calls with an empty stdin pipe.
if [[ -z "$snapshot" ]]; then
  snapshot=$(bash "$HERE/collect.sh")
fi

printf '%s' "$snapshot" | jq '
  {
    repo: .repo,
    generatedAt: .generatedAt,
    issues: {
      open:   ([.issues[] | select(.state == "OPEN")]   | length),
      closed: ([.issues[] | select(.state == "CLOSED")] | length)
    },
    pullRequests: (
      ([.pullRequests[] | select(.state == "OPEN")]) as $open
      | ([.pullRequests[] | select(.state == "OPEN" and .isDraft)]) as $draft
      | ([.pullRequests[]
          | select(.firstReviewAt != null and .mergedAt != null)
          | ((.firstReviewAt | fromdateiso8601) - (.createdAt | fromdateiso8601)) / 3600
        ]) as $latencies
      | {
          open:  ($open  | length),
          draft: ($draft | length),
          awaitingReview: ([$open[]
            | select(.isDraft | not)
            | select(.reviewDecision == null or .reviewDecision == "REVIEW_REQUIRED")
          ] | length),
          failingChecks: ([$open[]
            | select(.statusCheck == "FAILURE" or .statusCheck == "ERROR")
          ] | length),
          oldestOpenAgeDays: (
            ([$open[] | .createdAt | fromdateiso8601] | min) as $oldest
            | if $oldest then (((now - $oldest) / 86400) | floor) else null end
          ),
          avgTimeToFirstReviewHours: (
            if ($latencies | length) > 0
            then (($latencies | add) / ($latencies | length) | floor)
            else null
            end
          )
        }
    ),
    topLabels: (
      [.issues[] | select(.state == "OPEN") | .labels[]]
      | group_by(.) | map({name: .[0], count: length})
      | sort_by(-.count) | .[0:10]
    ),
    # One row per (assignee, open-issue) pair — multi-assignee issues now
    # contribute to every assignee, not just the first one (regression fix
    # vs the pre-PR-1 script, which took .assignees[0].login).
    byAssignee: (
      [.issues[]
        | select(.state == "OPEN")
        | (if (.assignees | length) == 0 then ["unassigned"] else .assignees end) as $who
        | $who[]
      ]
      | group_by(.) | map({login: .[0], count: length})
      | sort_by(-.count)
    ),
    oldestOpenPr: (
      [.pullRequests[] | select(.state == "OPEN")]
      | sort_by(.createdAt) | .[0]
      | if . then
          {number, title, createdAt, url, isDraft, reviewDecision, statusCheck}
        else null end
    )
  }
'
