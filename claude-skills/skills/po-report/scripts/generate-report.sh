#!/usr/bin/env bash
# generate-report.sh — compose a full PO markdown report.
# Calls the other scripts and emits markdown on stdout.
# Usage:
#   bash scripts/generate-report.sh > .claude/reports/$(date +%F)-status.md
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"

status_json=$(bash "${HERE}/status.sh")
milestones_json=$(bash "${HERE}/milestone-progress.sh")
stale_json=$(bash "${HERE}/stale-issues.sh" 14)

repo=$(printf '%s' "$status_json" | jq -r '.repo')
generated_at=$(printf '%s' "$status_json" | jq -r '.generatedAt')
open_issues=$(printf '%s' "$status_json" | jq -r '.issues.open')
closed_issues=$(printf '%s' "$status_json" | jq -r '.issues.closed')
open_prs=$(printf '%s' "$status_json" | jq -r '.pullRequests.open')
draft_prs=$(printf '%s' "$status_json" | jq -r '.pullRequests.draft')

cat <<MD
# PO Report — ${repo}

_Generated: ${generated_at}_

## At a glance

| Metric            | Value |
| ----------------- | ----- |
| Open issues       | ${open_issues} |
| Closed issues     | ${closed_issues} |
| Open PRs          | ${open_prs} |
| Draft PRs         | ${draft_prs} |

## Top labels (open issues)

$(printf '%s' "$status_json" | jq -r '
  if (.topLabels | length) == 0 then "_No labels._"
  else (["| Label | Count |", "| --- | --- |"] + (.topLabels | map("| \(.name) | \(.count) |"))) | join("\n")
  end
')

## Open issues by assignee

$(printf '%s' "$status_json" | jq -r '
  if (.byAssignee | length) == 0 then "_No open issues._"
  else (["| Assignee | Open |", "| --- | --- |"] + (.byAssignee | map("| \(.login) | \(.count) |"))) | join("\n")
  end
')

## Milestone progress

$(printf '%s' "$milestones_json" | jq -r '
  if length == 0 then "_No open milestones._"
  else (["| Milestone | Due | Closed/Total | % | URL |", "| --- | --- | --- | --- | --- |"]
        + (map("| \(.title) | \(.due_on // "—") | \(.closed_issues)/\(.total) | \(.percent_complete | floor)% | \(.url) |"))) | join("\n")
  end
')

## Stale open issues (no activity > 14 days)

$(printf '%s' "$stale_json" | jq -r '
  if length == 0 then "_None._"
  else (["| # | Title | Days stale | Assignees | Labels |", "| --- | --- | --- | --- | --- |"]
        + (.[0:25] | map("| [#\(.number)](\(.url)) | \(.title | gsub("\\|"; "\\\\|")) | \(.daysStale) | \((.assignees // []) | join(", ")) | \((.labels // []) | join(", ")) |"))) | join("\n")
  end
')

$(printf '%s' "$stale_json" | jq -r 'if length > 25 then "_Showing top 25 of \(length) stale issues._" else "" end')

## Oldest open PR

$(printf '%s' "$status_json" | jq -r '
  if .oldestOpenPr == null then "_No open PRs._"
  else "- [#\(.oldestOpenPr.number)](\(.oldestOpenPr.url)) — \(.oldestOpenPr.title) _(opened \(.oldestOpenPr.createdAt))_"
  end
')
MD
