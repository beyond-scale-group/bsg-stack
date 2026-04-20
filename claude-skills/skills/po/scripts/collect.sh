#!/usr/bin/env bash
# collect.sh — emit a single PO snapshot for the target repo as JSON.
#
# Every other script in this skill consumes this snapshot (via stdin or
# `--snapshot <file>`). No other script should call `gh` directly.
# Running `generate-report.sh` or the @po-manager agent collects once
# per run and reuses the result — one snapshot per report.
#
# The target repo is resolved in this order:
#   1. `$GH_REPO` env var (same convention as the `gh` CLI)
#   2. `gh repo view` auto-detection from the git remote
#
# Writes the JSON to stdout. No file I/O; the caller decides where to
# store it (agents write to `po/history/<date>.json`).
#
# Run from anywhere:
#   GH_REPO=owner/name bash collect.sh > /tmp/snapshot.json
#   bash collect.sh | jq '.issues | length'      # from a git checkout

set -euo pipefail

if ! command -v gh >/dev/null 2>&1; then
  echo '{"error":"gh CLI not found"}' >&2
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo '{"error":"jq not found"}' >&2
  exit 1
fi

# --- resolve target repo ---------------------------------------------------

if [[ -n "${GH_REPO:-}" ]]; then
  slug="${GH_REPO}"
else
  slug=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
fi
owner="${slug%%/*}"
name="${slug##*/}"

generated_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# --- issues (paginated, all states) ---------------------------------------
# Query every field any downstream report needs. `lastCommentedAt` is
# derived from `comments(last: 1)` rather than a direct field — GitHub
# GraphQL doesn't expose it directly.

issues_query='
query($owner: String!, $name: String!, $endCursor: String) {
  repository(owner: $owner, name: $name) {
    issues(first: 100, after: $endCursor, orderBy: {field: UPDATED_AT, direction: DESC}) {
      pageInfo { hasNextPage endCursor }
      nodes {
        number
        title
        state
        stateReason
        createdAt
        updatedAt
        closedAt
        url
        author { login }
        assignees(first: 10) { nodes { login } }
        labels(first: 30) { nodes { name } }
        milestone { title number dueOn state }
        reactions(first: 1, content: THUMBS_UP) { totalCount }
        comments(last: 1) { nodes { createdAt author { login } } }
      }
    }
  }
}'

issues=$(gh api graphql --paginate \
  -F owner="$owner" -F name="$name" \
  -f query="$issues_query" \
  --jq '.data.repository.issues.nodes | map({
    number,
    title,
    state,
    stateReason,
    createdAt,
    updatedAt,
    closedAt,
    url,
    author: .author.login,
    assignees: [.assignees.nodes[].login],
    labels: [.labels.nodes[].name],
    milestone: (if .milestone then {title: .milestone.title, number: .milestone.number, dueOn: .milestone.dueOn, state: .milestone.state} else null end),
    thumbsUp: (.reactions.totalCount // 0),
    lastCommentedAt: (.comments.nodes[0].createdAt // null),
    lastCommentBy: (.comments.nodes[0].author.login // null)
  })' | jq -s 'flatten')

# --- pull requests (paginated, all states, recent by updatedAt) -----------

prs_query='
query($owner: String!, $name: String!, $endCursor: String) {
  repository(owner: $owner, name: $name) {
    pullRequests(first: 100, after: $endCursor, orderBy: {field: UPDATED_AT, direction: DESC}) {
      pageInfo { hasNextPage endCursor }
      nodes {
        number
        title
        state
        isDraft
        createdAt
        updatedAt
        mergedAt
        closedAt
        url
        author { login }
        reviewDecision
        mergeStateStatus
        reviews(first: 50) {
          nodes { author { login } submittedAt state }
        }
        closingIssuesReferences(first: 10) { nodes { number } }
        labels(first: 30) { nodes { name } }
        statusCheckRollup { state }
        assignees(first: 10) { nodes { login } }
      }
    }
  }
}'

prs=$(gh api graphql --paginate \
  -F owner="$owner" -F name="$name" \
  -f query="$prs_query" \
  --jq '.data.repository.pullRequests.nodes | map({
    number,
    title,
    state,
    isDraft,
    createdAt,
    updatedAt,
    mergedAt,
    closedAt,
    url,
    author: .author.login,
    assignees: [.assignees.nodes[].login],
    labels: [.labels.nodes[].name],
    reviewDecision,
    mergeStateStatus,
    statusCheck: (.statusCheckRollup.state // null),
    closingIssues: [.closingIssuesReferences.nodes[].number],
    reviews: [.reviews.nodes[] | {author: .author.login, submittedAt: .submittedAt, state: .state}],
    firstReviewAt: ([.reviews.nodes[].submittedAt] | sort | .[0] // null)
  })' | jq -s 'flatten')

# --- milestones (REST — simpler and GraphQL progress fields are flaky) ----

milestones=$(gh api "repos/${owner}/${name}/milestones?state=all&per_page=100" \
  --jq '[.[] | {
    number, title, state,
    dueOn: .due_on,
    createdAt: .created_at,
    updatedAt: .updated_at,
    openIssues: .open_issues,
    closedIssues: .closed_issues,
    total: (.open_issues + .closed_issues),
    percentComplete: (
      if (.open_issues + .closed_issues) == 0 then 0
      else ((.closed_issues * 100) / (.open_issues + .closed_issues))
      end
    ),
    url: .html_url
  }]' 2>/dev/null || echo '[]')

# --- releases (latest 30) -------------------------------------------------

releases=$(gh api "repos/${owner}/${name}/releases?per_page=30" \
  --jq '[.[] | {tagName: .tag_name, name: .name, publishedAt: .published_at, url: .html_url, isDraft: .draft, isPrerelease: .prerelease}]' \
  2>/dev/null || echo '[]')

# --- repo metadata --------------------------------------------------------

repo_meta=$(gh api "repos/${owner}/${name}" \
  --jq '{
    topics: .topics,
    visibility: .visibility,
    defaultBranch: .default_branch,
    pushedAt: .pushed_at,
    isFork: .fork,
    parent: (if .parent then .parent.full_name else null end)
  }' 2>/dev/null || echo '{}')

# --- emit snapshot --------------------------------------------------------

jq -n \
  --arg repo "$slug" \
  --arg generatedAt "$generated_at" \
  --argjson meta "$repo_meta" \
  --argjson issues "$issues" \
  --argjson prs "$prs" \
  --argjson milestones "$milestones" \
  --argjson releases "$releases" \
  '{
    repo: $repo,
    generatedAt: $generatedAt,
    meta: $meta,
    issues: $issues,
    pullRequests: $prs,
    milestones: $milestones,
    releases: $releases
  }'
