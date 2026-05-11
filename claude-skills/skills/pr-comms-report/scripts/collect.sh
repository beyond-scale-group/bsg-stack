#!/usr/bin/env bash
# collect.sh — comms snapshot.
#
# Inventories: releases, milestones, security advisories, press-kit
# assets with freshness, ANNOUNCED.md entries, contributor counts,
# PR counts.

set -euo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$REPO_ROOT"

# shellcheck source=../../../scripts/_bsg-paths.sh disable=SC1091
source "$(dirname "$0")/../../../scripts/_bsg-paths.sh"

TODAY=$(date +%F)
TODAY_EPOCH=$(date -j -f "%Y-%m-%d" "$TODAY" +%s 2>/dev/null || date -d "$TODAY" +%s 2>/dev/null || echo 0)

# --------------------------------------------- releases

RELEASES_JSON='[]'
if command -v gh >/dev/null 2>&1; then
  RELEASES_JSON=$(gh release list --limit 30 \
    --json tagName,name,publishedAt,isDraft,isPrerelease,body 2>/dev/null \
    | jq '[.[] | select(.isDraft == false and .isPrerelease == false) |
        { tag: .tagName, title: (.name // .tagName), publishedAt: .publishedAt, body: (.body // "") }]' \
      2>/dev/null || echo '[]')
fi

# --------------------------------------------- milestones

MILESTONES_JSON='[]'
if command -v gh >/dev/null 2>&1; then
  MILESTONES_JSON=$(gh api /repos/{owner}/{repo}/milestones?state=all --paginate 2>/dev/null \
    | jq '[.[] | { number, title, state, closedAt: .closed_at, dueOn: .due_on, description }]' \
      2>/dev/null || echo '[]')
fi

# --------------------------------------------- security advisories

ADVISORIES_JSON='[]'
if command -v gh >/dev/null 2>&1; then
  ADVISORIES_JSON=$(gh api /repos/{owner}/{repo}/security-advisories 2>/dev/null \
    | jq '[.[]? | { ghsaId: .ghsa_id, cveId: .cve_id, severity, state, summary, publishedAt: .published_at }]' \
      2>/dev/null || echo '[]')
fi

# --------------------------------------------- press kit

PRESS_KIT_DIR="comms/press-kit"
PRESS_KIT_PRESENT="false"
PRESS_KIT_JSON='[]'
if [[ -d "$PRESS_KIT_DIR" ]]; then
  PRESS_KIT_PRESENT="true"
  PRESS_KIT_JSON=$(find "$PRESS_KIT_DIR" -type f -name '*.md' 2>/dev/null | while IFS= read -r f; do
    last_ts=$(git log -1 --format=%at -- "$f" 2>/dev/null || echo "0")
    if [[ "$last_ts" = "0" ]]; then
      # Not yet committed — use filesystem mtime.
      last_ts=$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null || echo "0")
    fi
    age_days=$(( (TODAY_EPOCH - last_ts) / 86400 ))
    last_date=$(date -r "$last_ts" +%F 2>/dev/null || echo "unknown")
    rel=${f#"$PRESS_KIT_DIR"/}
    jq -nc --arg file "$rel" --arg lastDate "$last_date" --argjson age "$age_days" \
      '{file: $file, lastUpdated: $lastDate, ageDays: $age}'
  done | jq -sc '.' 2>/dev/null || echo '[]')
fi

# --------------------------------------------- ANNOUNCED.md

ANNOUNCED_PATH="$(bsg_doc_path announced)"
ANNOUNCED_JSON='[]'
if [[ -f "$ANNOUNCED_PATH" ]]; then
  ANNOUNCED_JSON=$({ grep -oE '(v?[0-9]+\.[0-9]+\.[0-9]+|milestone #[0-9]+)' "$ANNOUNCED_PATH" || true; } \
    | sort -u | jq -Rn '[inputs]' 2>/dev/null || echo '[]')
fi

# --------------------------------------------- existing press releases

EXISTING_DRAFTS_JSON='[]'
if [[ -d comms/press-releases ]]; then
  EXISTING_DRAFTS_JSON=$(find comms/press-releases -type f -name '*.md' 2>/dev/null | while IFS= read -r f; do
    release=$(grep -m1 -E '^release:' "$f" 2>/dev/null | sed -E 's/release:[[:space:]]*//' || echo "")
    if [[ -z "$release" ]]; then
      release=$(basename "$f" | grep -oE 'v?[0-9]+(\.[0-9]+){1,2}' | head -1 || echo "")
    fi
    status=$(grep -m1 -E '^status:' "$f" 2>/dev/null | sed -E 's/status:[[:space:]]*//' || echo "unknown")
    jq -nc --arg file "$f" --arg release "$release" --arg status "$status" \
      '{file: $file, release: $release, status: $status}'
  done | jq -sc '.' 2>/dev/null || echo '[]')
fi

# --------------------------------------------- contributors + PR counts

CONTRIB_COUNT=$(git shortlog -sn HEAD 2>/dev/null | wc -l | tr -d ' ')
PR_MERGED_COUNT=0
if command -v gh >/dev/null 2>&1; then
  PR_MERGED_COUNT=$(gh pr list --state merged --limit 1 --json number 2>/dev/null | jq 'length // 0' 2>/dev/null || echo "0")
  # Total merged count: gh doesn't return a total, but search does.
  total=$(gh api -X GET /search/issues -f q="repo:$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null) is:pr is:merged" -f per_page=1 2>/dev/null \
    | jq '.total_count // 0' 2>/dev/null || echo "0")
  PR_MERGED_COUNT=$total
fi

# --------------------------------------------- repo visibility

REPO_VISIBILITY="unknown"
if command -v gh >/dev/null 2>&1; then
  REPO_VISIBILITY=$(gh repo view --json visibility -q .visibility 2>/dev/null | tr '[:upper:]' '[:lower:]' || echo "unknown")
fi

# --------------------------------------------- emit

jq -n \
  --arg repoRoot "$REPO_ROOT" \
  --arg generatedAt "$(date -u +%FT%TZ)" \
  --arg today "$TODAY" \
  --argjson releases "$RELEASES_JSON" \
  --argjson milestones "$MILESTONES_JSON" \
  --argjson advisories "$ADVISORIES_JSON" \
  --arg pressKitDir "$PRESS_KIT_DIR" \
  --arg pressKitPresent "$PRESS_KIT_PRESENT" \
  --argjson pressKit "$PRESS_KIT_JSON" \
  --argjson announced "$ANNOUNCED_JSON" \
  --argjson existingDrafts "$EXISTING_DRAFTS_JSON" \
  --argjson contributors "$CONTRIB_COUNT" \
  --argjson prsMerged "$PR_MERGED_COUNT" \
  --arg visibility "$REPO_VISIBILITY" \
  '{
    repoRoot: $repoRoot,
    generatedAt: $generatedAt,
    today: $today,
    visibility: $visibility,
    releases: $releases,
    milestones: $milestones,
    securityAdvisories: $advisories,
    pressKit: {
      directory: $pressKitDir,
      present: ($pressKitPresent == "true"),
      assets: $pressKit
    },
    announced: $announced,
    existingDrafts: $existingDrafts,
    contributors: $contributors,
    prsMerged: $prsMerged
  }'
