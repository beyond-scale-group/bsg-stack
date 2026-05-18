#!/usr/bin/env bash
# init-narrative.sh — generate a draft NARRATIVE.md from repo scan.
#
# Part of #237 (per-agent --init contract): scans the repo for brand
# narrative signals (repo description, README "About"/mission sections,
# package metadata, recent README headings) and emits a draft
# `.bsg/NARRATIVE.md` to stdout. The storytelling agent reads this file
# every tick to audit voice consistency across public-facing assets.
#
# The orchestrator (`/bsg-stack init`) captures stdout and opens a PR
# for human review — this script never writes to disk.
#
# Usage:
#   bash init-narrative.sh
#   bash init-narrative.sh --repo OWNER/NAME

set -euo pipefail

REPO_FLAG=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_FLAG=(--repo "$2"); shift 2 ;;
    -h|--help) sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "init-narrative.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$REPO_ROOT"

today=$(date -u +%F)

# ----------------------------------------------- signals

repo_name="unknown"
description=""
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  meta=$(gh repo view "${REPO_FLAG[@]}" --json name,description 2>/dev/null || echo '{}')
  repo_name=$(jq -r '.name // "unknown"' <<<"$meta")
  description=$(jq -r '.description // ""' <<<"$meta")
fi

# Fallback for repo name from package.json / pyproject.
if [[ "$repo_name" == "unknown" && -f package.json ]]; then
  candidate=$(jq -r '.name // empty' package.json 2>/dev/null || true)
  [[ -n "$candidate" ]] && repo_name="$candidate"
fi

# Strip a leading "owner/" if gh returned the qualified name.
repo_name="${repo_name##*/}"

# README first paragraph after the H1 — usually the "about" pitch.
readme_pitch=""
if [[ -f README.md ]]; then
  readme_pitch=$(awk '
    /^#[^#]/ { found_h1=1; next }
    found_h1 && /^[[:space:]]*$/ {
      if (started) exit
      else next
    }
    found_h1 {
      if (substr($0,1,1) == "#") exit
      started=1
      print
    }
  ' README.md | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g;s/^[[:space:]]+|[[:space:]]+$//g')
fi

# Fall back to description when the README pitch is empty.
positioning="${readme_pitch:-$description}"
[[ -z "$positioning" ]] && positioning="_Replace this with a one-line positioning statement._"

# ----------------------------------------------- emit

cat <<HEAD
# Narrative bible — ${repo_name}

_Draft bootstrapped ${today}. Edit and commit to \`.bsg/NARRATIVE.md\` —
the storytelling agent reads this file every tick to audit voice and
positioning across README, docs, and marketing copy._

## Positioning

**Category:** _e.g. "developer tools / infrastructure / SaaS — set this."_
**Target audience:** _e.g. "platform engineers at growth-stage startups — set this."_
**Feature anchors:** _3-5 features that anchor the product story._

**One-line positioning:**

> ${positioning}

## Voice Guidelines

**Tone target:** 7.0

_Score on a 1–10 scale (1 = corporate-formal, 10 = friendly-conversational).
The storytelling agent measures Flesch reading ease against this target._

**Banned vocabulary:** synergy, leverage, paradigm, robust, seamless, holistic, actionable, scalable, disruptive, best-in-class, world-class, cutting-edge, next-generation, enterprise-grade

_Comma-separated terms the agent will flag in any public copy.
Add domain-specific buzzwords your team wants to avoid._

**Preferred vocabulary:**

_Comma-separated alternatives to push for. Leave empty if no
team-wide convention exists yet._

## Key Messages

_3-5 core messages that should land in any external communication.
The storytelling agent checks each public asset for coverage._

1. _Replace this with your primary message — usually the "why" of the product._
2. _Replace this with the second core message — typically the "what makes us different"._
3. _Replace this with the third core message — often a proof point or signature feature._

## Value Proposition

_Bullets explaining what makes this product distinctive. The agent
treats each bullet as a differentiator to look for in copy._

- _Set this — what does this product do that nothing else does?_
- _Set this — what trade-off does this product make explicit?_
- _Set this — who is the product NOT for? (Sharper positioning.)_
HEAD
