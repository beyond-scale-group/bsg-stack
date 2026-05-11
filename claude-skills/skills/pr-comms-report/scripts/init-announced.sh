#!/usr/bin/env bash
# init-announced.sh — generate a draft ANNOUNCED.md from repo scan.
#
# Part of #237 (per-agent --init contract): scans the repo's published
# releases (and CHANGELOG entries if present), emits a draft
# `.bsg/ANNOUNCED.md` to stdout listing items that have already been
# communicated externally. The pr-comms agent reads this file to avoid
# re-drafting press releases for already-announced events.
#
# The orchestrator (`/bsg-stack init`) captures stdout and opens a PR
# for human review — this script never writes to disk.
#
# Usage:
#   bash init-announced.sh           # auto-scan current repo
#   bash init-announced.sh --repo OWNER/NAME

set -euo pipefail

REPO_FLAG=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_FLAG=(--repo "$2"); shift 2 ;;
    -h|--help) sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "init-announced.sh: unknown arg: $1" >&2; exit 2 ;;
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
  releases_json=$(gh release list "${REPO_FLAG[@]}" --limit 100 \
    --json tagName,publishedAt,name,isDraft,isPrerelease 2>/dev/null \
    | jq '[.[] | select(.isDraft == false and .isPrerelease == false)
           | {tag: .tagName, date: (.publishedAt | split("T")[0]), title: (.name // .tagName)}]' \
      2>/dev/null || echo '[]')
fi

# ----------------------------------------------- emit

cat <<HEAD
# Announced events — ${repo_name}

_Draft bootstrapped ${today}. Edit and commit to \`.bsg/ANNOUNCED.md\` —
the pr-comms agent reads this file to skip already-communicated events
when scanning for newsworthy items._

## Already announced

_Pulled from \`gh release list\` (drafts and pre-releases excluded).
Each line is a release tag plus the date it was published. Add manual
rows for milestones, partner news, or blog posts that already shipped._

HEAD

if [[ "$(jq 'length' <<<"$releases_json")" -gt 0 ]]; then
  jq -r '.[] | "- \(.tag) — \(.title) (\(.date))"' <<<"$releases_json"
else
  echo "- _No published releases yet._"
fi

# CHANGELOG version headers as additional signal.
if [[ -f CHANGELOG.md ]]; then
  cat <<'CHANGELOG_HEADER'

## CHANGELOG version markers

_Detected from CHANGELOG.md. These usually align with releases but are
listed separately so you can spot gaps where a CHANGELOG entry exists
without a matching release announcement._

CHANGELOG_HEADER
  grep -oE '^##+\s*\[?v?[0-9]+\.[0-9]+(\.[0-9]+)?\]?' CHANGELOG.md 2>/dev/null \
    | sed -E 's/^##+[[:space:]]*//;s/^\[//;s/\]$//' \
    | head -20 \
    | awk '{print "- " $0}' \
    || echo "- _No version markers parsed._"
fi

cat <<'TAIL'

## How to use

The pr-comms agent treats any release tag or milestone reference appearing
in this file as "already communicated" — it won't re-draft an announcement
for it. Append new entries here when you ship something that's been
publicly announced (blog post, social media, partner press).
TAIL
