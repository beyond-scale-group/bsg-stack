#!/usr/bin/env bash
# milestone-progress.sh — list open milestones with progress as JSON.
# No arguments. Run from repo root.
set -euo pipefail

if ! command -v gh >/dev/null 2>&1; then
  echo '{"error":"gh CLI not found"}' >&2
  exit 1
fi

# Resolve owner/repo from gh
slug=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
owner="${slug%%/*}"
name="${slug##*/}"

# Use REST API for milestones (gh CLI has no top-level milestone command).
# state=open keeps the noise down; switch to all if you need closed too.
gh api "repos/${owner}/${name}/milestones?state=open&per_page=100" \
  --jq '[ .[] | {
      number: .number,
      title: .title,
      state: .state,
      due_on: .due_on,
      open_issues: .open_issues,
      closed_issues: .closed_issues,
      total: (.open_issues + .closed_issues),
      percent_complete: (
        if (.open_issues + .closed_issues) == 0 then 0
        else ((.closed_issues * 100) / (.open_issues + .closed_issues))
        end
      ),
      url: .html_url
    } ]'
