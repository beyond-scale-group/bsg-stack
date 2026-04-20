#!/usr/bin/env bash
# pr-flow.sh — dedicated PR flow metrics, as JSON.
#
# A deeper look at the PR queue than status.sh's summary row: review
# latency percentiles, merge-queue depth, oldest draft, reviewer load,
# and the full distribution of open-PR age buckets.
#
# Reads a collect.sh snapshot via `--snapshot <path>`, stdin, or
# auto-run. Output:
#
#   {
#     "reviewLatencyHours": { "p50": 12, "p90": 48, "max": 72, "sampleSize": N },
#     "openPrs": { "total": N, "drafts": N, "awaitingReview": N, "failingChecks": N,
#                  "withMergeConflicts": N, "ageBuckets": {...}, "oldest": {...} },
#     "reviewerLoad": [ { "login": "...", "pendingReviews": N } ],
#     "mergeQueue": { "depth": N, "entries": [...] },
#     "throughput": { "mergedLast30d": N, "mergedPerWeek": N.N }
#   }
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
  (now) as $now
  | (.pullRequests) as $prs
  | ([$prs[] | select(.state == "OPEN")]) as $open

  # --- review latency (hours from createdAt → firstReviewAt) on merged PRs ---
  | ([$prs[]
      | select(.firstReviewAt != null and .createdAt != null)
      | (((.firstReviewAt | fromdateiso8601) - (.createdAt | fromdateiso8601)) / 3600)
      | floor
    ] | sort) as $latencies

  | (
      if ($latencies | length) == 0 then
        {p50: null, p90: null, max: null, sampleSize: 0}
      else
        ($latencies | length) as $n
        | {
            p50:        ($latencies[(($n * 50)  / 100) | floor]),
            p90:        ($latencies[(($n * 90)  / 100) | floor]),
            max:        ($latencies[-1]),
            sampleSize: $n
          }
      end
    ) as $latencyStats

  # --- open-PR age buckets ---
  | ([$open[] | ((($now - (.createdAt | fromdateiso8601)) / 86400) | floor)]) as $ages
  | {
      le1d:   ([$ages[] | select(. <= 1)]   | length),
      le7d:   ([$ages[] | select(. > 1  and . <= 7)]  | length),
      le30d:  ([$ages[] | select(. > 7  and . <= 30)] | length),
      gt30d:  ([$ages[] | select(. > 30)] | length)
    } as $ageBuckets

  # --- reviewer load: pending REVIEW_REQUIRED PRs grouped by assigned reviewer ---
  # Best proxy we have without pagination of reviewRequests: count PRs where
  # the latest review from a given user is PENDING, or count authors of the
  # most recent review per PR.
  | ([$open[]
      | select(.reviewDecision == "REVIEW_REQUIRED" or .reviewDecision == null)
      | .reviews[]?
      | select(.state == "PENDING" or .state == "COMMENTED")
      | .author
     ]
     | group_by(.) | map({login: .[0], pendingReviews: length})
     | sort_by(-.pendingReviews) | .[0:5]
    ) as $reviewerLoad

  # --- merge queue (mergeStateStatus is the best signal available) ---
  | ([$open[] | select(.mergeStateStatus == "BLOCKED" or .mergeStateStatus == "UNSTABLE")]) as $queueish

  # --- throughput: PRs merged in the last 30 days ---
  | ([$prs[]
      | select(.mergedAt != null)
      | .mergedAt | fromdateiso8601
      | select($now - . <= 30 * 86400)
     ]) as $mergedRecent
  | {
      reviewLatencyHours: $latencyStats,
      openPrs: {
        total:              ($open | length),
        drafts:             ([$open[] | select(.isDraft)] | length),
        awaitingReview:     ([$open[]
                              | select(.isDraft | not)
                              | select(.reviewDecision == null or .reviewDecision == "REVIEW_REQUIRED")
                             ] | length),
        failingChecks:      ([$open[] | select(.statusCheck == "FAILURE" or .statusCheck == "ERROR")] | length),
        withMergeConflicts: ([$open[] | select(.mergeStateStatus == "DIRTY")] | length),
        ageBuckets:         $ageBuckets,
        oldest:             ([$open[]] | sort_by(.createdAt) | .[0]
                             | if . then {number, title, url, createdAt, author,
                                           ageDays: (((now - (.createdAt | fromdateiso8601)) / 86400) | floor)}
                               else null end)
      },
      reviewerLoad: $reviewerLoad,
      mergeQueue: {
        depth:   ($queueish | length),
        entries: ($queueish | map({number, title, url, mergeStateStatus}))
      },
      throughput: {
        mergedLast30d: ($mergedRecent | length),
        mergedPerWeek: ((($mergedRecent | length) / 4.28 * 100 | floor) / 100)
      }
    }
'
