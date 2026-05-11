#!/usr/bin/env bash
# init-keywords.sh — generate a draft KEYWORDS.md from repo scan.
#
# Part of #237 (per-agent --init contract): scans the repo for seed
# keywords drawn from the repo description, topics, package metadata,
# and README headings, then emits a draft `.bsg/KEYWORDS.md` to stdout.
# The orchestrator (`/bsg-stack init`) captures stdout and opens a PR
# for human review — this script never writes to disk.
#
# Usage:
#   bash init-keywords.sh           # auto-scan current repo
#   bash init-keywords.sh --repo OWNER/NAME
#
# Exit 0 + content on stdout: success
# Exit 0 + empty stdout: nothing to seed (no signals found)
# Exit 1: error (missing tool, no gh auth, etc.)

set -euo pipefail

REPO_FLAG=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_FLAG=(--repo "$2"); shift 2 ;;
    -h|--help) sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "init-keywords.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$REPO_ROOT"

today=$(date -u +%F)

# ----------------------------------------------- signal collection

repo_name="unknown"
description=""
topics_json='[]'
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  meta=$(gh repo view "${REPO_FLAG[@]}" --json name,description,repositoryTopics 2>/dev/null || echo '{}')
  repo_name=$(jq -r '.name // "unknown"' <<<"$meta")
  description=$(jq -r '.description // ""' <<<"$meta")
  topics_json=$(jq '[.repositoryTopics[]?.name]' <<<"$meta")
fi

# README headings (H1/H2) as candidate keywords.
headings_json='[]'
if [[ -f README.md ]]; then
  headings_json=$(grep -E '^#{1,2} ' README.md 2>/dev/null \
    | sed -E 's/^#+[[:space:]]*//' \
    | head -10 \
    | jq -Rn '[inputs | select(length > 0)]' || echo '[]')
fi

# package.json keywords if present.
package_keywords_json='[]'
if [[ -f package.json ]]; then
  package_keywords_json=$(jq '.keywords // []' package.json 2>/dev/null || echo '[]')
fi

# ----------------------------------------------- emit

cat <<HEAD
# Keywords — ${repo_name}

_Draft bootstrapped ${today}. Edit and commit to \`.bsg/KEYWORDS.md\` —
the seo agent reads this file every tick to score keyword coverage._

## Target keywords

_The bullets below are seeded from repo description, topics, package
metadata, and README headings. Replace, dedupe, and prioritize._

HEAD

# Merge all signal sources, dedupe, lowercase, emit as bullets.
{
  [[ -n "$description" ]] && echo "$description"
  jq -r '.[]?' <<<"$topics_json"
  jq -r '.[]?' <<<"$headings_json"
  jq -r '.[]?' <<<"$package_keywords_json"
} 2>/dev/null \
  | tr ',' '\n' \
  | sed -E 's/^[[:space:]]+|[[:space:]]+$//g' \
  | awk 'NF > 0 && !seen[tolower($0)]++ { print "- " $0 }' \
  | head -25 \
  | { read -r first; if [[ -z "$first" ]]; then
      echo "- _No signals found — author this list manually._"
    else
      printf '%s\n' "$first"
      cat
    fi
  }

cat <<'TAIL'

## Coverage notes

_The seo agent will fill this section on each tick with which keywords
appear in your public pages (README, docs/, marketing/) and which
need stronger coverage. Leave it empty on first commit._
TAIL
