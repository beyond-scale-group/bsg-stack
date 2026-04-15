#!/usr/bin/env bash
# generate-report.sh — compose a full PO markdown report from one snapshot.
#
# Collects once via collect.sh and feeds that snapshot into every
# downstream script. The snapshot itself should be committed to
# `po/history/<date>.json` by the caller (the @po-manager agent writes
# it there); this script only emits the rendered markdown on stdout.
#
# Usage:
#   bash generate-report.sh > po/reports/$(date +%F)-status.md
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"

snapshot=$(bash "$HERE/collect.sh")
status_json=$(printf '%s' "$snapshot"     | bash "$HERE/status.sh")
milestones_json=$(printf '%s' "$snapshot" | bash "$HERE/milestone-progress.sh")
stale_json=$(printf '%s' "$snapshot"      | bash "$HERE/stale-issues.sh" 14)

# Adherence is the headline section when a PLAN.md exists. Reuse the
# already-collected snapshot so adherence.sh doesn't re-fetch. Rendering
# lives in a standalone jq file to keep shell-heredoc escaping sane.
snapshot_tmp=$(mktemp)
printf '%s' "$snapshot" > "$snapshot_tmp"
adherence_json=$(bash "$HERE/adherence.sh" --snapshot "$snapshot_tmp")
adherence_md=$(printf '%s' "$adherence_json" | jq -r -f "$HERE/render-adherence.jq")
rm -f "$snapshot_tmp"

repo=$(printf '%s' "$status_json"      | jq -r '.repo')
generated_at=$(printf '%s' "$status_json" | jq -r '.generatedAt')
open_issues=$(printf '%s' "$status_json"   | jq -r '.issues.open')
closed_issues=$(printf '%s' "$status_json" | jq -r '.issues.closed')
open_prs=$(printf '%s' "$status_json"      | jq -r '.pullRequests.open')
draft_prs=$(printf '%s' "$status_json"     | jq -r '.pullRequests.draft')
awaiting_review=$(printf '%s' "$status_json"  | jq -r '.pullRequests.awaitingReview')
failing_checks=$(printf '%s' "$status_json"   | jq -r '.pullRequests.failingChecks')
oldest_pr_age=$(printf '%s' "$status_json"    | jq -r '.pullRequests.oldestOpenAgeDays // "—"')
avg_review_h=$(printf '%s' "$status_json"     | jq -r '.pullRequests.avgTimeToFirstReviewHours // "—"')

cat <<MD
# PO Report — ${repo}

_Generated: ${generated_at}_

## Plan adherence

${adherence_md}

## At a glance

| Metric                         | Value |
| ------------------------------ | ----- |
| Open issues                    | ${open_issues} |
| Closed issues                  | ${closed_issues} |
| Open PRs                       | ${open_prs} |
| Draft PRs                      | ${draft_prs} |
| PRs awaiting review            | ${awaiting_review} |
| PRs with failing checks        | ${failing_checks} |
| Oldest open PR (days)          | ${oldest_pr_age} |
| Avg time to first review (h)   | ${avg_review_h} |

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
  else
    (
      ["| Milestone | Due | Days left | Closed/Total | % | Flags |",
       "| --- | --- | --- | --- | --- | --- |"]
      + (map(
          (
            [ if .flags.overdue      then "overdue"      else empty end,
              if .flags.at_risk      then "at-risk"      else empty end,
              if .flags.understaffed then "understaffed" else empty end,
              if .flags.stalled      then "stalled"      else empty end
            ] | join(", ")
          ) as $flags
          | "| \(.title) | \(.dueOn // "—") | \(.daysRemaining // "—") | \(.closedIssues)/\(.total) | \(.percentComplete | floor)% | \($flags) |"
        ))
    ) | join("\n")
  end
')

## Stale open issues (no comment activity > 14 days)

$(printf '%s' "$stale_json" | jq -r '
  if length == 0 then "_None._"
  else (["| # | Title | Days stale | Last comment | Assignees | Labels |",
         "| --- | --- | --- | --- | --- | --- |"]
        + (.[0:25] | map("| [#\(.number)](\(.url)) | \(.title | gsub("\\|"; "\\\\|")) | \(.daysStale) | \(.lastCommentedAt // "—") | \((.assignees // []) | join(", ")) | \((.labels // []) | join(", ")) |"))) | join("\n")
  end
')

$(printf '%s' "$stale_json" | jq -r 'if length > 25 then "_Showing top 25 of \(length) stale issues._" else "" end')

## Oldest open PR

$(printf '%s' "$status_json" | jq -r '
  if .oldestOpenPr == null then "_No open PRs._"
  else
    "- [#\(.oldestOpenPr.number)](\(.oldestOpenPr.url)) — \(.oldestOpenPr.title) _(opened \(.oldestOpenPr.createdAt); review: \(.oldestOpenPr.reviewDecision // "pending"); checks: \(.oldestOpenPr.statusCheck // "—"))_"
  end
')
MD
