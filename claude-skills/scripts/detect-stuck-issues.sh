#!/usr/bin/env bash
# detect-stuck-issues.sh — flag and escalate eligible-but-unimplemented issues.
#
# An issue is "stuck" when it is fully eligible for the autopilot pilot
# (carries bus + type + milestone, no open PR referencing it), yet hasn't
# moved in N days. Stuck flow is the autopilot's silent failure mode —
# the agent picked nothing up because of budget, scope contract, or
# circuit-breaker, and nobody noticed.
#
# Two-tier escalation aligned with the principle "humans are the
# fallback, not the default":
#
#   Tier 1 — STUCK_DAYS_NUDGE (default 2 days):
#     Post a comment on the issue tagging the owning agent
#     (`@<bus_label>`) and prompting another tick attempt. No human
#     intervention. Add `stuck:nudged` label so the next tier can fire.
#
#   Tier 2 — STUCK_DAYS_ESCALATE (default 5 days):
#     The agent hasn't been able to make progress despite the nudge —
#     spec is likely ambiguous or the tech choice isn't tranched.
#     Assign the issue to `default_human_reviewer` from
#     .bsg-autopilot.yml, post a comment with `@<human>` mention, and
#     apply `needs:spec-clarification` + `needs-human-review`.
#
# Idempotent: each tier applies its label and won't re-fire on the
# same tier. Once tier 2 fires, the issue is human-owned until the
# human removes `needs:spec-clarification` (which un-stuckes it).
#
# Usage:
#   detect-stuck-issues.sh [--repo OWNER/NAME] [--dry-run]
#                          [--nudge-days N] [--escalate-days N]
#
# Emits one line per stuck issue acted upon (JSON: number, tier, action).
# Exit 0 always — silent run when nothing is stuck.

set -euo pipefail

REPO_FLAG=()
DRY_RUN=false
NUDGE_DAYS=2
ESCALATE_DAYS=5

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_FLAG=(--repo "$2"); shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --nudge-days) NUDGE_DAYS="$2"; shift 2 ;;
    --escalate-days) ESCALATE_DAYS="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "detect-stuck-issues.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done

# Read default_human_reviewer from .bsg-autopilot.yml. If absent, tier 2
# escalation falls back to the issue creator (next best human).
HUMAN_REVIEWER=""
if [[ -f .bsg-autopilot.yml ]]; then
  HUMAN_REVIEWER=$(grep -E '^\s*default_human_reviewer\s*:' .bsg-autopilot.yml 2>/dev/null \
    | head -1 | sed 's/.*:\s*//' | tr -d '[:space:]"' | tr -d "'")
fi

# Bootstrap the labels we may apply (idempotent).
ensure_label() {
  local name="$1" color="$2" desc="$3"
  if ! gh label list "${REPO_FLAG[@]}" --json name \
       --jq '.[] | select(.name == "'"$name"'") | .name' \
       2>/dev/null | grep -qx "$name"; then
    gh label create "$name" "${REPO_FLAG[@]}" \
      --color "$color" --description "$desc" >/dev/null 2>&1 || true
  fi
}

ensure_label "stuck:nudged" "fbca04" "detect-stuck-issues: tier-1 nudge applied (idempotent marker)"
ensure_label "needs:spec-clarification" "d93f0b" "Awaiting human spec clarification — agent could not proceed"

# Compute cutoff timestamps (BSD/GNU date compatible — both ship on macOS
# and Linux runners). Use python3 as a portable fallback.
to_iso_back() {
  local days="$1"
  python3 -c "
import datetime
print((datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=$days)).strftime('%Y-%m-%dT%H:%M:%SZ'))
"
}

NUDGE_CUTOFF=$(to_iso_back "$NUDGE_DAYS")
ESCALATE_CUTOFF=$(to_iso_back "$ESCALATE_DAYS")

# Pull all open eligible-shaped issues (bus + type + milestone). We
# filter for actually-stuck ones (no open PR referencing them) below.
all_eligible=$(gh issue list "${REPO_FLAG[@]}" \
  --state open \
  --json number,title,labels,milestone,updatedAt,author \
  --limit 200 2>/dev/null || echo "[]")

# Filter via jq: must have bus + type + milestone, must not already
# carry needs:spec-clarification (already escalated).
candidates=$(jq -c '
  .[]
  | select(.labels | any(.name == "tech" or .name == "qa" or .name == "seo"))
  | select(.labels | any(.name == "bug" or .name == "enhancement"))
  | select(.milestone != null)
  | select(.labels | any(.name == "needs:spec-clarification") | not)
  | {
      number,
      title,
      updatedAt,
      author: (.author.login // "unknown"),
      bus: ([.labels[] | select(.name == "tech" or .name == "qa" or .name == "seo") | .name] | first),
      already_nudged: (.labels | any(.name == "stuck:nudged"))
    }
' <<<"$all_eligible")

if [[ -z "$candidates" ]]; then
  exit 0
fi

# For each candidate, check there is no open PR referencing it.
echo "$candidates" | while read -r cand; do
  num=$(jq -r '.number' <<<"$cand")
  title=$(jq -r '.title' <<<"$cand")
  updated_at=$(jq -r '.updatedAt' <<<"$cand")
  author=$(jq -r '.author' <<<"$cand")
  bus=$(jq -r '.bus' <<<"$cand")
  already_nudged=$(jq -r '.already_nudged' <<<"$cand")

  # Skip if there's an open PR referencing the issue (work in flight).
  pr_count=$(gh pr list "${REPO_FLAG[@]}" \
    --state open --search "fixes #$num OR closes #$num" \
    --json number --limit 1 2>/dev/null | jq 'length' 2>/dev/null || echo "0")
  if [[ "$pr_count" -gt 0 ]]; then
    continue
  fi

  # Determine tier by comparing updatedAt to cutoffs (string comparison
  # works because all timestamps are RFC3339 UTC).
  tier=""
  if [[ "$updated_at" < "$ESCALATE_CUTOFF" ]]; then
    tier="escalate"
  elif [[ "$updated_at" < "$NUDGE_CUTOFF" && "$already_nudged" == "false" ]]; then
    tier="nudge"
  fi

  if [[ -z "$tier" ]]; then
    continue
  fi

  jq -nc --arg n "$num" --arg t "$tier" --arg b "$bus" --arg u "$updated_at" \
    '{number: ($n | tonumber), tier: $t, bus: $b, last_update: $u}'

  if [[ "$DRY_RUN" == "true" ]]; then
    continue
  fi

  if [[ "$tier" == "nudge" ]]; then
    gh issue comment "$num" "${REPO_FLAG[@]}" --body "@${bus} this issue has been eligible for the autopilot pilot for ${NUDGE_DAYS}+ days without progress. Likely causes: budget cap (\`max_loc_per_issue\`), circuit-breaker (\`max_prs_per_day\`), or scope contract rejection. Please re-attempt or comment with the blocker." >/dev/null 2>&1 || true
    gh issue edit "$num" "${REPO_FLAG[@]}" --add-label "stuck:nudged" >/dev/null 2>&1 || true
  elif [[ "$tier" == "escalate" ]]; then
    target_human="${HUMAN_REVIEWER:-$author}"
    gh issue comment "$num" "${REPO_FLAG[@]}" --body "@${target_human} this issue has been stuck for ${ESCALATE_DAYS}+ days despite agent nudges. Likely cause: spec ambiguity or unresolved tech choice. Please clarify the spec or split the work — then remove \`needs:spec-clarification\` to put the issue back in the pipeline." >/dev/null 2>&1 || true
    gh issue edit "$num" "${REPO_FLAG[@]}" \
      --add-label "needs:spec-clarification" \
      --add-label "needs-human-review" \
      --add-assignee "$target_human" >/dev/null 2>&1 || true
  fi
done

exit 0
