#!/usr/bin/env bash
# collect.sh — marketing snapshot.
#
# Parses CALENDAR.md (resolved via _bsg-paths.sh — `.bsg/CALENDAR.md`
# preferred, legacy `marketing/CALENDAR.md` fallback per ADR-001),
# lists recent releases and milestones via gh, globs marketing /
# README / docs files and extracts their H1/H2 headings as "claims"
# for alignment analysis.

set -euo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$REPO_ROOT"

# shellcheck source=../../../scripts/_bsg-paths.sh disable=SC1091
source "$(dirname "$0")/../../../scripts/_bsg-paths.sh"

TODAY=$(date +%F)
TODAY_EPOCH=$(date -j -f "%Y-%m-%d" "$TODAY" +%s 2>/dev/null || date -d "$TODAY" +%s 2>/dev/null || echo 0)

# -------------------------------------------- calendar

CALENDAR_PATH="$(bsg_doc_path calendar)"
CALENDAR_FOUND="false"
CALENDAR_ITEMS_JSON='[]'
if [[ -f "$CALENDAR_PATH" ]]; then
  CALENDAR_FOUND="true"
  CALENDAR_ITEMS_JSON=$({ grep -nE '^-[[:space:]]\[([ x])\][[:space:]]+[0-9]{4}-[0-9]{2}-[0-9]{2}' "$CALENDAR_PATH" || true; } \
    | while IFS= read -r line; do
        # Strip leading "<lineno>:"
        stripped=${line#*:}
        # Example: - [ ] 2026-04-15 — Blog: API v2 launch
        checked=$(echo "$stripped" | grep -oE '\[[ x]\]' | head -1 | tr -d '[] ')
        completed=$([ "$checked" = "x" ] && echo true || echo false)
        date=$(echo "$stripped" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1)
        title=$(echo "$stripped" | sed -E 's/.*[0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]]*[—-]?[[:space:]]*//')
        item_epoch=$(date -j -f "%Y-%m-%d" "$date" +%s 2>/dev/null || date -d "$date" +%s 2>/dev/null || echo 0)
        diff_days=$(( (TODAY_EPOCH - item_epoch) / 86400 ))
        jq -nc --arg date "$date" --arg title "$title" --argjson completed "$completed" --argjson diff "$diff_days" '
          { date: $date, title: $title, completed: $completed, daysFromToday: $diff }
        '
      done \
    | jq -sc '.' 2>/dev/null || echo '[]')
fi

# -------------------------------------------- releases

RELEASES_JSON='[]'
if command -v gh >/dev/null 2>&1; then
  RELEASES_JSON=$(gh release list --limit 30 \
    --json tagName,name,publishedAt,isDraft,isPrerelease 2>/dev/null \
    | jq '[.[] | select(.isDraft == false and .isPrerelease == false) | {
        tag: .tagName,
        title: (.name // .tagName),
        releasedAt: .publishedAt
      }]' 2>/dev/null || echo '[]')
fi

# -------------------------------------------- milestones

MILESTONES_JSON='[]'
if command -v gh >/dev/null 2>&1; then
  MILESTONES_JSON=$(gh api /repos/{owner}/{repo}/milestones?state=all --paginate 2>/dev/null \
    | jq '[.[] | {
        number,
        title,
        state,
        closedAt: .closed_at,
        dueOn: .due_on,
        description
      }]' 2>/dev/null || echo '[]')
fi

# -------------------------------------------- marketing content

# File kinds:
#   marketing/**  — marketing source
#   README.md     — top-level overview
#   docs/**       — technical docs, subset counts as marketing (landing, pricing, features)
#
# Claims: H1 and H2 headings extracted from each file.

collect_claims() {
  local f=$1
  [[ -f "$f" ]] || return
  local claims_json
  claims_json=$({ grep -E '^#{1,2}[[:space:]]+' "$f" || true; } \
    | sed -E 's/^#{1,2}[[:space:]]+//' \
    | head -20 \
    | jq -Rn '[inputs]' 2>/dev/null || echo '[]')
  jq -nc --arg file "$f" --argjson claims "$claims_json" '{file: $file, claims: $claims}'
}

MARKETED_JSON='[]'
{
  # marketing/**
  if [[ -d marketing ]]; then
    find marketing -type f -name '*.md' 2>/dev/null | while IFS= read -r f; do
      collect_claims "$f"
    done
  fi
  # README
  [[ -f README.md ]] && collect_claims README.md
  # docs/ focused subset
  if [[ -d docs ]]; then
    find docs -type f -name '*.md' 2>/dev/null | grep -iE '(landing|pricing|feature|product)' | while IFS= read -r f; do
      collect_claims "$f"
    done
  fi
} > /tmp/marketing-claims.$$.jsonl 2>/dev/null || true
MARKETED_JSON=$(jq -sc '.' /tmp/marketing-claims.$$.jsonl 2>/dev/null || echo '[]')
rm -f /tmp/marketing-claims.$$.jsonl

# -------------------------------------------- existing briefs

BRIEFS_JSON='[]'
if [[ -d marketing/briefs ]]; then
  BRIEFS_JSON=$(find marketing/briefs -type f -name '*.md' 2>/dev/null | while IFS= read -r f; do
    # Extract the release tag from either frontmatter or filename.
    release=$(grep -m1 -E '^release:' "$f" 2>/dev/null | sed -E 's/release:[[:space:]]*//' || echo "")
    if [[ -z "$release" ]]; then
      release=$(basename "$f" | grep -oE 'v?[0-9]+(\.[0-9]+){1,2}' | head -1 || echo "")
    fi
    status=$(grep -m1 -E '^status:' "$f" 2>/dev/null | sed -E 's/status:[[:space:]]*//' || echo "unknown")
    # age via git log (first-seen)
    first_ts=$(git log --format=%at -- "$f" 2>/dev/null | tail -1 || echo "0")
    age_days=$(( (TODAY_EPOCH - first_ts) / 86400 ))
    jq -nc --arg path "$f" --arg release "$release" --arg status "$status" --argjson age "$age_days" \
      '{path: $path, release: $release, status: $status, age: $age}'
  done | jq -sc '.' 2>/dev/null || echo '[]')
fi

# ---------------------------------------------------------- emit

jq -n \
  --arg repoRoot "$REPO_ROOT" \
  --arg generatedAt "$(date -u +%FT%TZ)" \
  --arg today "$TODAY" \
  --arg calendarPath "$CALENDAR_PATH" \
  --arg calendarFound "$CALENDAR_FOUND" \
  --argjson calendarItems "$CALENDAR_ITEMS_JSON" \
  --argjson releases "$RELEASES_JSON" \
  --argjson milestones "$MILESTONES_JSON" \
  --argjson marketed "$MARKETED_JSON" \
  --argjson briefs "$BRIEFS_JSON" \
  '{
    repoRoot: $repoRoot,
    generatedAt: $generatedAt,
    today: $today,
    calendar: {
      path: $calendarPath,
      found: ($calendarFound == "true"),
      items: $calendarItems
    },
    releases: $releases,
    milestones: $milestones,
    marketed: $marketed,
    briefs: $briefs
  }'
