#!/usr/bin/env bash
# migrate-epics-to-milestones.sh — one-shot idempotent migration: epic:E* labels → GitHub milestones.
#
# Phase 2a of E10 label-simplification (#287).
#
# For each label of the form `epic:E*` in the target repo:
#   1. Create a GitHub milestone with the same name (stripping the "epic:" prefix).
#   2. For every open issue or PR carrying that label, assign the milestone.
#
# The script is idempotent: skip milestone creation if it already exists,
# skip assignment if the item already carries the correct milestone.
#
# Usage:
#   bash claude-skills/scripts/migrate-epics-to-milestones.sh --dry-run    # preview only
#   bash claude-skills/scripts/migrate-epics-to-milestones.sh --apply      # execute
#
# Optional flags:
#   --repo OWNER/NAME   target repo (default: current repo from git remote)
#   --dry-run           print actions without executing (default if neither flag given)
#   --apply             execute the migration
#
# Dependencies: gh (GitHub CLI), jq
#
# Exit codes:
#   0 — success (or dry-run completed)
#   1 — fatal error (missing dependency, bad args)

set -euo pipefail

DRY_RUN=true
REPO_FLAG=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)  DRY_RUN=true; shift ;;
    --apply)    DRY_RUN=false; shift ;;
    --repo)     REPO_FLAG=(--repo "$2"); shift 2 ;;
    -h|--help)
      sed -n '2,/^[^#]/p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "migrate-epics-to-milestones.sh: unknown arg: $1" >&2; exit 1 ;;
  esac
done

# Verify dependencies.
if ! command -v gh &>/dev/null; then
  echo "ERROR: gh (GitHub CLI) is required" >&2; exit 1
fi
if ! command -v jq &>/dev/null; then
  echo "ERROR: jq is required" >&2; exit 1
fi

if "$DRY_RUN"; then
  echo "[dry-run] No changes will be made. Pass --apply to execute."
fi

# ---- Step 1: Enumerate epic:E* labels in the target repo ----
epic_labels=$(gh label list "${REPO_FLAG[@]}" \
  --search "epic:" \
  --json name \
  --jq '.[].name | select(startswith("epic:E"))' 2>/dev/null || true)

if [[ -z "$epic_labels" ]]; then
  echo "No epic:E* labels found — nothing to migrate."
  exit 0
fi

echo "Found epic labels to migrate:"
echo "$epic_labels" | sed 's/^/  /'

# ---- Step 2: For each label, ensure its milestone exists ----

# Fetch current milestones once.
existing_milestones=$(gh api "${REPO_FLAG[@]:+${REPO_FLAG[*]}}" \
  repos/:owner/:repo/milestones \
  --paginate \
  --jq '[.[].title]' 2>/dev/null || echo "[]")

maybe_run() {
  # maybe_run <description> <command...>
  local desc="$1"; shift
  if "$DRY_RUN"; then
    echo "[dry-run] $desc"
  else
    echo "[apply] $desc"
    "$@"
  fi
}

while IFS= read -r label; do
  # Strip "epic:" prefix to get the milestone name.
  milestone_name="${label#epic:}"

  # Check if milestone already exists.
  already_exists=$(echo "$existing_milestones" | jq -r --arg m "$milestone_name" 'any(.[]; . == $m)')

  if [[ "$already_exists" == "true" ]]; then
    echo "  milestone '$milestone_name' already exists — skipping creation"
  else
    maybe_run "create milestone '$milestone_name'" \
      gh api "${REPO_FLAG[@]:+${REPO_FLAG[*]}}" \
        repos/:owner/:repo/milestones \
        --method POST \
        --field title="$milestone_name" \
        --silent
  fi

  # ---- Step 3: Assign milestone to all open issues/PRs with this label ----
  items=$(gh issue list "${REPO_FLAG[@]}" \
    --state open \
    --label "$label" \
    --json number,milestone \
    --jq '.[]' 2>/dev/null || true)

  if [[ -z "$items" ]]; then
    echo "  no open issues with label '$label'"
    continue
  fi

  while IFS= read -r item; do
    num=$(echo "$item" | jq -r '.number')
    current_ms=$(echo "$item" | jq -r '.milestone.title // ""')

    if [[ "$current_ms" == "$milestone_name" ]]; then
      echo "  #$num already has milestone '$milestone_name' — skipping"
      continue
    fi

    maybe_run "assign milestone '$milestone_name' to #$num (currently: '${current_ms:-none}')" \
      gh issue edit "$num" "${REPO_FLAG[@]}" \
        --milestone "$milestone_name"
  done < <(echo "$items")

done < <(echo "$epic_labels")

echo ""
if "$DRY_RUN"; then
  echo "Dry-run complete. Re-run with --apply to execute."
else
  echo "Migration complete."
fi
