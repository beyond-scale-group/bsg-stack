#!/usr/bin/env bash
# normalize-issue-labels.sh — auto-route open issues into the autopilot
# pipeline by adding missing type and bus labels.
#
# `list-pilot-candidates.sh` requires three labels per issue: a bus label
# (tech/qa/seo), a type label (bug/enhancement), and a milestone. Issues
# missing any one of those sit in the backlog forever even when they're
# fully specified — the pipeline just can't see them.
#
# This script normalizes labels at every PO tick (step 1.4) so the
# pipeline becomes the default path. Goal: maximize auto-implementation,
# minimize human routing decisions. Mis-routes are cheap and self-
# correcting — the receiving agent rejects out-of-scope work and swaps
# the label. A ticket waiting for a human to apply a label is expensive.
#
# Three normalization cases:
#
#   Cas A — has bus label, missing type:
#     Add `enhancement` automatically.
#
#   Cas B — has type label, missing bus:
#     Infer bus from keywords in title/body and apply it. Also apply
#     `needs:<inferred>` so the issue becomes a phase-B candidate on the
#     next sweep. Post a comment naming the inferred route so a human
#     (or another agent) can swap if the inference is wrong.
#
#   Cas C — neither bus nor type, but milestone assigned:
#     Apply Cas A + Cas B in one shot (the milestone proves the issue is
#     real work, not a draft).
#
# Inference rules — multi-word phrase match against title + body. Single
# words like "test" or "meta" are too noisy (a meta-repo discussion or a
# "test the helper" body would mis-route). Tech is the strong default —
# false positives on qa/seo are more expensive than tech catching extra
# work since tech is the largest backlog.
#
#   qa:    "test coverage", "flaky test", "regression test", "coverage
#          report", "test suite", "pytest", "vitest", "jest", "ci flake"
#   seo:   "meta tag", "meta description", "<meta ", "canonical url",
#          "sitemap.xml", "robots.txt", "og:", "schema.org", "hreflang",
#          "open graph", "structured data"
#   tech:  default — anything that isn't qa or seo
#
# Cap at `max_issues_per_tick` from .bsg-autopilot.yml (default 10) per
# run so a single tick can't flood the repo if a backlog of unrouted
# issues just landed.
#
# Idempotent — running twice is a no-op.
#
# Usage:
#   bash claude-skills/scripts/normalize-issue-labels.sh [--repo OWNER/NAME] [--dry-run]
#
# Emits one line per normalized issue (JSON). Empty output = nothing to
# normalize. Exit 0 always (no work is not an error).

set -euo pipefail

# shellcheck source=_bsg-paths.sh disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/_bsg-paths.sh"

REPO_FLAG=()
DRY_RUN=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_FLAG=(--repo "$2"); shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help)
      sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "normalize-issue-labels.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done

# Cap per tick — read from .bsg-autopilot.yml.
MAX_ISSUES=10
if [[ -f "$BSG_AUTOPILOT_FILE" ]]; then
  configured=$(grep -E '^\s*max_issues_per_tick\s*:' "$BSG_AUTOPILOT_FILE" 2>/dev/null \
    | head -1 | sed 's/.*:\s*//' | tr -d '[:space:]')
  if [[ -n "$configured" ]]; then
    MAX_ISSUES="$configured"
  fi
fi

# Bus labels we route to. Order matters for inference fallback.
BUS_LABELS_OUTPUT_COMMIT=("tech" "qa" "seo")

infer_bus_label() {
  # $1 = title + body lowercased.
  local text="$1"
  if echo "$text" | grep -qE 'test coverage|flaky test|regression test|coverage report|test suite|\bpytest\b|\bvitest\b|\bjest\b|ci flake|ci-flake'; then
    echo "qa"
  elif echo "$text" | grep -qE 'meta tag|meta description|<meta |canonical url|sitemap\.xml|robots\.txt|og:|schema\.org|hreflang|open graph|structured data'; then
    echo "seo"
  else
    echo "tech"
  fi
}

has_label() {
  # $1 = labels JSON array, $2 = label name to check
  jq -e --arg n "$2" 'any(.name == $n)' <<<"$1" >/dev/null 2>&1
}

has_any_bus_label() {
  # $1 = labels JSON array
  local lbl
  for lbl in "${BUS_LABELS_OUTPUT_COMMIT[@]}"; do
    if has_label "$1" "$lbl"; then
      return 0
    fi
  done
  return 1
}

# Pull all open issues with their labels, milestone, title, body.
all_open=$(gh issue list "${REPO_FLAG[@]}" \
  --state open \
  --json number,title,body,labels,milestone \
  --limit 200 2>/dev/null || echo "[]")

count=0
echo "$all_open" | jq -c '.[]' | while read -r issue; do
  # Stop when we hit the cap (writing to a counter file because subshell).
  if [[ $count -ge $MAX_ISSUES ]]; then
    break
  fi

  num=$(jq -r '.number' <<<"$issue")
  title=$(jq -r '.title' <<<"$issue")
  body=$(jq -r '.body // ""' <<<"$issue")
  labels=$(jq -c '.labels' <<<"$issue")
  milestone=$(jq -r '.milestone.title // empty' <<<"$issue")

  has_type=false
  has_bus=false
  has_label "$labels" "bug" && has_type=true
  has_label "$labels" "enhancement" && has_type=true
  has_any_bus_label "$labels" && has_bus=true

  # Skip if already fully labeled.
  if [[ "$has_type" == "true" && "$has_bus" == "true" ]]; then
    continue
  fi

  # Cas C requires a milestone (otherwise the issue is too raw to route).
  if [[ "$has_type" == "false" && "$has_bus" == "false" && -z "$milestone" ]]; then
    continue
  fi

  added_labels=()
  case_name=""

  if [[ "$has_bus" == "true" && "$has_type" == "false" ]]; then
    case_name="A"
    added_labels+=("enhancement")
  elif [[ "$has_bus" == "false" && "$has_type" == "true" ]]; then
    case_name="B"
    inferred=$(infer_bus_label "$(echo "$title $body" | tr '[:upper:]' '[:lower:]')")
    added_labels+=("$inferred")
    added_labels+=("needs:$inferred")
  elif [[ "$has_bus" == "false" && "$has_type" == "false" && -n "$milestone" ]]; then
    case_name="C"
    inferred=$(infer_bus_label "$(echo "$title $body" | tr '[:upper:]' '[:lower:]')")
    added_labels+=("$inferred")
    added_labels+=("needs:$inferred")
    added_labels+=("enhancement")
  else
    continue
  fi

  # Emit JSON record (always, dry-run or not).
  jq -nc --arg n "$num" --arg t "$title" --arg c "$case_name" \
        --argjson labels "$(printf '%s\n' "${added_labels[@]}" | jq -R . | jq -s .)" \
        '{number: ($n | tonumber), title: $t, case: $c, added: $labels}'

  if [[ "$DRY_RUN" == "true" ]]; then
    count=$((count + 1))
    continue
  fi

  # Apply the labels.
  for lbl in "${added_labels[@]}"; do
    gh issue edit "$num" "${REPO_FLAG[@]}" --add-label "$lbl" >/dev/null 2>&1 || true
  done

  # For Cas B and C, post a transparency comment so the inferred route is
  # visible and a human or another agent can correct it cheaply.
  if [[ "$case_name" != "A" ]]; then
    inferred_only=""
    for lbl in "${added_labels[@]}"; do
      case "$lbl" in
        tech|qa|seo) inferred_only="$lbl"; break ;;
      esac
    done
    gh issue comment "$num" "${REPO_FLAG[@]}" --body "Auto-routed to \`${inferred_only}\` by \`normalize-issue-labels.sh\` (case ${case_name}, keyword inference). If the inference is wrong, swap the bus label — the next sweep will pick up the correct routing." >/dev/null 2>&1 || true
  fi

  count=$((count + 1))
done

exit 0
