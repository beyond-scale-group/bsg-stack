#!/usr/bin/env bash
# status.sh — emit repo-wide PO metrics as JSON.
# No arguments. Run from repo root. Requires `gh` authenticated.
set -euo pipefail

if ! command -v gh >/dev/null 2>&1; then
  echo '{"error":"gh CLI not found"}' >&2
  exit 1
fi

# Pull each metric independently so a partial failure doesn't tank the whole thing.
open_issues=$(gh issue list --state open    --limit 1000 --json number --jq 'length' 2>/dev/null || echo 0)
closed_issues=$(gh issue list --state closed --limit 1000 --json number --jq 'length' 2>/dev/null || echo 0)
open_prs=$(gh pr list      --state open    --limit 1000 --json number --jq 'length' 2>/dev/null || echo 0)
draft_prs=$(gh pr list     --state open    --limit 1000 --json number,isDraft --jq '[.[] | select(.isDraft)] | length' 2>/dev/null || echo 0)

# Top labels on open issues
top_labels=$(gh issue list --state open --limit 1000 \
  --json labels \
  --jq '[.[].labels[].name] | group_by(.) | map({name: .[0], count: length}) | sort_by(-.count) | .[0:10]' \
  2>/dev/null || echo '[]')

# Open issues by assignee (unassigned first)
by_assignee=$(gh issue list --state open --limit 1000 \
  --json assignees \
  --jq '[.[] | (if (.assignees|length)==0 then "unassigned" else .assignees[0].login end)] | group_by(.) | map({login: .[0], count: length}) | sort_by(-.count)' \
  2>/dev/null || echo '[]')

# Oldest open PR (for "review queue depth" signal)
oldest_open_pr=$(gh pr list --state open --limit 1000 \
  --json number,title,createdAt,url \
  --jq 'sort_by(.createdAt) | .[0] // null' \
  2>/dev/null || echo 'null')

repo=$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null || echo 'unknown')
generated_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)

cat <<JSON
{
  "repo": "${repo}",
  "generatedAt": "${generated_at}",
  "issues": {
    "open": ${open_issues},
    "closed": ${closed_issues}
  },
  "pullRequests": {
    "open": ${open_prs},
    "draft": ${draft_prs}
  },
  "topLabels": ${top_labels},
  "byAssignee": ${by_assignee},
  "oldestOpenPr": ${oldest_open_pr}
}
JSON
