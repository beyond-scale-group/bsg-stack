#!/usr/bin/env bash
# pilot-circuit-breaker.sh — daily cap on implementation PRs.
#
# Counts PRs opened today by the pilot agents (title matches
# `fix(*-pilot):`) and compares against the max_prs_per_day budget
# from .bsg-autopilot.yml (default: 3). Exits 0 if under budget,
# exits 1 if at or over budget.
#
# Usage:
#   bash claude-skills/scripts/pilot-circuit-breaker.sh [--repo OWNER/NAME]
#
# The caller's tick should check the exit code before entering phase (B).

set -euo pipefail

REPO_FLAG=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)  REPO_FLAG=(--repo "$2"); shift 2 ;;
    -h|--help)
      sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "pilot-circuit-breaker.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done

MAX_PRS=3

if [[ -f .bsg-autopilot.yml ]]; then
  parsed=$(grep -E '^\s*max_prs_per_day\s*:' .bsg-autopilot.yml 2>/dev/null | head -1 | sed 's/.*:\s*//' | tr -d '[:space:]')
  if [[ -n "$parsed" && "$parsed" =~ ^[0-9]+$ ]]; then
    MAX_PRS="$parsed"
  fi
fi

today=$(date +%Y-%m-%d)

count=$(gh pr list "${REPO_FLAG[@]}" \
  --state all \
  --search "fix( in:title -pilot): in:title created:${today}" \
  --json number \
  --limit 200 2>/dev/null | jq 'length' 2>/dev/null || echo "0")

if [[ "$count" -ge "$MAX_PRS" ]]; then
  echo "circuit-breaker: $count/$MAX_PRS pilot PRs today — at limit, skipping phase (B)"
  exit 1
fi

exit 0
