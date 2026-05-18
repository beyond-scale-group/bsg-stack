#!/usr/bin/env bash
# init-calendar.sh — generate a draft CALENDAR.md from repo scan.
#
# Part of #237 (per-agent --init contract): scans the repo's recent
# releases and open milestones, emits a draft `.bsg/CALENDAR.md` to
# stdout. The orchestrator (`/bsg-stack init`) captures stdout and
# opens a PR for human review — this script never writes to disk.
#
# Usage:
#   bash init-calendar.sh           # auto-scan current repo
#   bash init-calendar.sh --repo OWNER/NAME
#
# Exit 0 + content on stdout: success
# Exit 1: error (missing tool, no gh auth, etc.)

set -euo pipefail

REPO_FLAG=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_FLAG=(--repo "$2"); shift 2 ;;
    -h|--help) sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "init-calendar.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$REPO_ROOT"

today=$(date -u +%F)

# ----------------------------------------------- signals

repo_name="unknown"
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  repo_name=$(gh repo view "${REPO_FLAG[@]}" --json name --jq '.name // "unknown"' 2>/dev/null || echo "unknown")
fi

releases_json='[]'
if command -v gh >/dev/null 2>&1; then
  releases_json=$(gh release list "${REPO_FLAG[@]}" --limit 10 \
    --json tagName,publishedAt,name 2>/dev/null \
    | jq '[.[] | {tag: .tagName, date: (.publishedAt | split("T")[0]), title: (.name // .tagName)}]' \
      2>/dev/null || echo '[]')
fi

milestones_json='[]'
if command -v gh >/dev/null 2>&1; then
  milestones_json=$(gh api "${REPO_FLAG[@]/#--repo/-X GET}" "/repos/{owner}/{repo}/milestones?state=open" 2>/dev/null \
    | jq '[.[] | {title: .title, due: (.due_on | split("T")[0] // null)}]' \
      2>/dev/null || echo '[]')
fi

# ----------------------------------------------- emit

cat <<HEAD
# Editorial calendar — ${repo_name}

_Draft bootstrapped ${today}. Edit and commit to \`.bsg/CALENDAR.md\` —
the marketing agent reads this file every tick to audit alignment
between scheduled comms and shipped features._

## Past releases (already shipped)

_Pulled from \`gh release list\`. Past dates are checked by default._

HEAD

if [[ "$(jq 'length' <<<"$releases_json")" -gt 0 ]]; then
  jq -r '.[] | "- [x] \(.date) — Release: \(.title)"' <<<"$releases_json"
else
  echo "- _No releases found in this repo yet._"
fi

cat <<'MID'

## Upcoming work (milestones)

_Pulled from open milestones with due dates. Edit to mark explicit comms.
Add additional rows for blog posts, social, partner mentions._

MID

if [[ "$(jq 'length' <<<"$milestones_json")" -gt 0 ]]; then
  jq -r '.[] | if .due then "- [ ] \(.due) — Milestone: \(.title)" else "- [ ] TBD — Milestone: \(.title)" end' <<<"$milestones_json"
else
  echo "- _No open milestones yet — add comms entries by hand._"
fi

cat <<'TAIL'

## Cadence

_Document your editorial cadence here (e.g. "blog every 2 weeks",
"product update each milestone"). The marketing agent uses this to
detect gaps._

- _Cadence not yet defined._
TAIL
