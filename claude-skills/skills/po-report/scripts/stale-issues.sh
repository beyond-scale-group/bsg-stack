#!/usr/bin/env bash
# stale-issues.sh [DAYS] — list open issues with no activity for N days.
# Default: 14 days. Run from repo root.
set -euo pipefail

DAYS="${1:-14}"

if ! command -v gh >/dev/null 2>&1; then
  echo '{"error":"gh CLI not found"}' >&2
  exit 1
fi

# Compute the cutoff in UTC. Use python for portability (BSD vs GNU date).
cutoff=$(python3 -c "
from datetime import datetime, timedelta, timezone
print((datetime.now(timezone.utc) - timedelta(days=${DAYS})).strftime('%Y-%m-%dT%H:%M:%SZ'))
")

gh issue list --state open --limit 1000 \
  --json number,title,assignees,labels,updatedAt,url \
  --jq "
    [ .[]
      | select(.updatedAt < \"${cutoff}\")
      | {
          number,
          title,
          assignees: [.assignees[].login],
          labels: [.labels[].name],
          updatedAt,
          daysStale: (((now - (.updatedAt | fromdateiso8601)) / 86400) | floor),
          url
        }
    ]
    | sort_by(-.daysStale)
  "
