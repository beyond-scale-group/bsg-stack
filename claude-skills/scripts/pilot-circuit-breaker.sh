#!/usr/bin/env bash
# pilot-circuit-breaker.sh — daily cap on implementation PRs.
#
# Counts PRs opened today by the pilot agents (title matches
# `fix(pilot):`) and compares against the max_prs_per_day budget
# from .bsg-autopilot.yml (default: 3). Exits 0 if under budget,
# exits 1 if at or over budget.
#
# max_prs_per_day can be a scalar (global cap) or a map with per-bus
# caps and a _default fallback:
#
#   budget:
#     max_prs_per_day: 200          # scalar — backward-compat
#
#   budget:
#     max_prs_per_day:              # map — per-bus caps
#       _default: 200
#       tech: 50
#       qa: 30
#
# Usage:
#   bash claude-skills/scripts/pilot-circuit-breaker.sh [--bus <name>] [--repo OWNER/NAME]
#
# --bus <name>  When max_prs_per_day is a map, look up the cap for <name>
#               (falling back to _default). Also filters the PR count by
#               the bus label so each bus counts only its own PRs.
#
# The caller's tick should check the exit code before entering phase (B).

set -euo pipefail

# shellcheck source=_bsg-paths.sh disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/_bsg-paths.sh"

REPO_FLAG=()
BUS=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)  REPO_FLAG=(--repo "$2"); shift 2 ;;
    --bus)   BUS="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "pilot-circuit-breaker.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done

DEFAULT_CAP=3
MAX_PRS=$DEFAULT_CAP

if [[ -f "$BSG_AUTOPILOT_FILE" ]]; then
  # Detect whether max_prs_per_day is a scalar or a map.
  # A scalar appears as:   max_prs_per_day: 200
  # A map appears as:      max_prs_per_day:\n    _default: 200\n    tech: 50
  # Note: grep -E and awk on macOS do not support \s — use [ \t]* instead.
  scalar=$(grep -E '^[ \t]*max_prs_per_day[ \t]*:[ \t]*[0-9]+[ \t]*$' "$BSG_AUTOPILOT_FILE" 2>/dev/null \
             | head -1 | sed 's/.*:[ \t]*//' | tr -d '[:space:]' || true)

  if [[ -n "$scalar" && "$scalar" =~ ^[0-9]+$ ]]; then
    # Scalar format — backward-compat global cap
    MAX_PRS="$scalar"
  elif [[ -n "$BUS" ]]; then
    # Map format — extract lines indented under max_prs_per_day:
    # (macOS awk does not support \s; use character classes)
    map_block=$(awk '
      /^[ \t]*max_prs_per_day[ \t]*:[ \t]*$/ { in_block=1; next }
      in_block && /^[^ \t]/ { in_block=0 }
      in_block { print }
    ' "$BSG_AUTOPILOT_FILE")

    bus_cap=$(echo "$map_block" \
      | grep -E "^[ \t]+${BUS}[ \t]*:[ \t]*[0-9]+" \
      | head -1 | sed 's/.*:[ \t]*//' | tr -d '[:space:]' || true)

    default_cap=$(echo "$map_block" \
      | grep -E "^[ \t]+_default[ \t]*:[ \t]*[0-9]+" \
      | head -1 | sed 's/.*:[ \t]*//' | tr -d '[:space:]' || true)

    if [[ -n "$bus_cap" && "$bus_cap" =~ ^[0-9]+$ ]]; then
      MAX_PRS="$bus_cap"
    elif [[ -n "$default_cap" && "$default_cap" =~ ^[0-9]+$ ]]; then
      MAX_PRS="$default_cap"
    fi
    # else: no map entry and no _default → keep DEFAULT_CAP
  fi
  # If map format but no --bus provided, fall back to DEFAULT_CAP (safe default)
fi

today=$(date +%Y-%m-%d)

# Build the search query. When a bus is specified, additionally filter by label
# so each bus counts only its own pilot PRs.
if [[ -n "$BUS" ]]; then
  count=$(gh pr list "${REPO_FLAG[@]}" \
    --state all \
    --search "fix(pilot): in:title created:${today} label:${BUS}" \
    --json number,labels \
    --limit 200 2>/dev/null | jq 'length' 2>/dev/null || echo "0")
else
  count=$(gh pr list "${REPO_FLAG[@]}" \
    --state all \
    --search "fix(pilot): in:title created:${today}" \
    --json number \
    --limit 200 2>/dev/null | jq 'length' 2>/dev/null || echo "0")
fi

if [[ "$count" -ge "$MAX_PRS" ]]; then
  echo "circuit-breaker: $count/$MAX_PRS pilot PRs today${BUS:+ for bus=$BUS} — at limit, skipping phase (B)"
  exit 1
fi

exit 0
