#!/usr/bin/env bash
# po-decompose-oversized.sh — flag open issues whose estimated LOC exceeds
# the autopilot budget so the PO can decompose them into sub-issues.
#
# Closes #363 fix #4. The output:commit pilot enforces a per-issue LOC
# cap (`max_loc_per_issue` from $BSG_AUTOPILOT_FILE). Issues above the
# cap never get picked up — they sit in the backlog forever. This
# script identifies them so the PO can split each one into sub-tickets
# that fit the budget.
#
# What it does:
#
#   1. Read `max_loc_per_issue` from $BSG_AUTOPILOT_FILE (default 200)
#   2. Enumerate open issues that have a bus label (tech/qa/seo) AND
#      are bound to a milestone — i.e. they would normally be phase-B
#      candidates if they fit the budget.
#   3. Estimate LOC for each issue from explicit hints in the body:
#        - "estimated_loc: N"
#        - "estimated LOC: N"
#        - "~N LOC", "~N lines"
#      When no hint is found, fall back to a body-length heuristic:
#      issues with > 60 lines of body are treated as "likely oversized"
#      and flagged for the PO to size manually.
#   4. Emit a JSONL stream of oversized issues — one per line:
#        {"number": N, "title": "...", "estimated_loc": N|null,
#         "agent": "tech", "milestone": "..."}
#   5. The PO reads this list and (optionally) files sub-issue stubs
#      with `file-issue.sh --type enhancement`. This script does NOT
#      create issues itself — the PO is the judge of whether to split,
#      defer, or rescope.
#
# Usage:
#   bash claude-skills/scripts/po-decompose-oversized.sh [--repo OWNER/NAME]
#
# Exit 0 always (no oversized issues is not an error).

set -euo pipefail

# shellcheck source=_bsg-paths.sh disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/_bsg-paths.sh"

REPO_FLAG=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_FLAG=(--repo "$2"); shift 2 ;;
    -h|--help)
      sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "po-decompose-oversized.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done

# Read max_loc_per_issue from $BSG_AUTOPILOT_FILE — fall back to 200.
MAX_LOC=200
if [[ -f "$BSG_AUTOPILOT_FILE" ]]; then
  configured=$(grep -E '^\s*max_loc_per_issue\s*:' "$BSG_AUTOPILOT_FILE" 2>/dev/null \
    | head -1 | sed 's/.*:\s*//' | tr -d '[:space:]' || true)
  if [[ -n "$configured" ]]; then
    MAX_LOC="$configured"
  fi
fi

# Bus labels we route to (`output: commit` agents).
BUS_LABELS=("tech" "qa" "seo")

emit_jsonl() {
  local agent="$1"
  gh issue list "${REPO_FLAG[@]}" \
    --state open \
    --label "$agent" \
    --json number,title,body,milestone,labels \
    --limit 200 2>/dev/null \
    | jq -c --arg agent "$agent" --argjson cap "$MAX_LOC" '
        .[]
        | select(.milestone != null)
        | . as $iss
        | (
            # Try to extract an explicit LOC hint from the body.
            ($iss.body // "")
            | (
                capture("estimated[_ ]loc[: ]+(?<n>[0-9]+)"; "i").n //
                capture("~\\s*(?<n>[0-9]+)\\s+(?:LOC|lines)"; "i").n //
                empty
              )
            | tonumber
          ) as $explicit
        | (($iss.body // "") | split("\n") | length) as $body_lines
        | if $explicit then
            (if $explicit > $cap then
              {number: $iss.number, title: $iss.title, estimated_loc: $explicit,
               agent: $agent, milestone: $iss.milestone.title, reason: "explicit-hint"}
             else empty end)
          elif $body_lines > 60 then
            {number: $iss.number, title: $iss.title, estimated_loc: null,
             agent: $agent, milestone: $iss.milestone.title,
             reason: "body-length>60 (no explicit estimate)"}
          else empty end
      '
}

for label in "${BUS_LABELS[@]}"; do
  emit_jsonl "$label"
done
