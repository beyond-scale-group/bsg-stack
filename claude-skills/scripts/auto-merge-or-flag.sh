#!/usr/bin/env bash
# auto-merge-or-flag.sh — finalize an implementation PR opened by an
# output:commit agent.
#
# Default behavior (safe): apply `needs-human-review` and stop. A human
# decides when to merge via `mark-reviewed.sh`.
#
# Auto-merge behavior: if `.bsg-autopilot.yml` exists with
# `enabled: true`, lists the calling agent under `agents:`, AND has
# `auto_merge: true`, this script squash-merges the PR, deletes the
# branch, and stamps `human-reviewed` instead. Use this only on
# repos where:
#   - Branch protection on main does not require reviews
#   - The 30 LOC / 3 file pilot budget + peer review are accepted
#     as the only quality gates
#
# bsg-stack opts in as the demonstrator repo. Other repos using the
# cached agents stay on the human-review default unless they too set
# auto_merge: true.
#
# Usage:
#   bash claude-skills/scripts/auto-merge-or-flag.sh <pr-number> <agent>
#
# Example:
#   bash claude-skills/scripts/auto-merge-or-flag.sh 249 tech

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=claude-skills/scripts/github-bus.sh
source "$SCRIPT_DIR/github-bus.sh"

if [[ $# -lt 2 ]]; then
  echo "usage: $0 <pr-number> <agent>" >&2
  exit 2
fi

PR_NUMBER="$1"
AGENT="$2"

AUTOPILOT_FILE=".bsg-autopilot.yml"
AUTO_MERGE=false

if [[ -f "$AUTOPILOT_FILE" ]]; then
  enabled=$(grep -E '^\s*enabled\s*:' "$AUTOPILOT_FILE" 2>/dev/null | head -1 | sed 's/.*:\s*//' | tr -d '[:space:]')
  auto_merge=$(grep -E '^\s*auto_merge\s*:' "$AUTOPILOT_FILE" 2>/dev/null | head -1 | sed 's/.*:\s*//' | tr -d '[:space:]')
  if [[ "$enabled" == "true" ]] && [[ "$auto_merge" == "true" ]]; then
    if grep -qE "^\s*-\s+$AGENT\s*$" "$AUTOPILOT_FILE" 2>/dev/null; then
      AUTO_MERGE=true
    fi
  fi
fi

# Resolve the linked issue from the PR body (Fixes/Closes/Refs #NN).
LINKED_ISSUE=""
LINKED_ISSUE=$(gh pr view "$PR_NUMBER" --json body --jq '.body' \
  | grep -oE '(Fixes|Closes|Refs) #[0-9]+' | head -1 \
  | grep -oE '[0-9]+') || true

if [[ "$AUTO_MERGE" == "true" ]]; then
  echo "auto-merge-or-flag: PR #${PR_NUMBER} ← squash + human-reviewed (autopilot)"
  # Swap labels BEFORE merging — `gh pr edit` after `--delete-branch` can hit
  # a transient eventual-consistency window where the edit silently no-ops.
  gh pr edit "$PR_NUMBER" --add-label human-reviewed --remove-label needs-human-review >/dev/null 2>&1 || true
  # Capture the head ref before merging — `gh pr merge --delete-branch`
  # nukes the remote branch, but a local worktree may still reference it
  # and we want to clean that up too (#363).
  HEAD_REF=$(gh pr view "$PR_NUMBER" --json headRefName --jq '.headRefName' 2>/dev/null || echo "")
  gh pr merge "$PR_NUMBER" --squash --delete-branch >/dev/null
  # Post-merge cleanup: if a local worktree was checked out on this
  # branch, remove it and delete the local branch ref. Best-effort —
  # never fail the merge over cleanup. See #363.
  if [[ -n "$HEAD_REF" ]]; then
    wt_path=$(git worktree list --porcelain \
      | awk -v b="refs/heads/$HEAD_REF" '
          $1 == "worktree" {p=$2}
          $1 == "branch" && $2 == b {print p; exit}
        ')
    if [[ -n "$wt_path" ]]; then
      git worktree unlock "$wt_path" 2>/dev/null || true
      git worktree remove --force "$wt_path" 2>/dev/null || true
    fi
    git branch -D "$HEAD_REF" 2>/dev/null || true
  fi
  [[ -n "$LINKED_ISSUE" ]] && bus_unlock "$LINKED_ISSUE" "$AGENT" || true
  # Advance the PO inbox: drop needs:<agent> from the linked issue so the
  # next tick picks the next priority claim. #199 (E7-bus-activation).
  [[ -n "$LINKED_ISSUE" ]] && gh issue edit "$LINKED_ISSUE" --remove-label "needs:$AGENT" >/dev/null 2>&1 || true
else
  echo "auto-merge-or-flag: PR #${PR_NUMBER} ← needs-human-review (default)"
  gh pr edit "$PR_NUMBER" --add-label needs-human-review >/dev/null
  [[ -n "$LINKED_ISSUE" ]] && bus_unlock "$LINKED_ISSUE" "$AGENT" || true
  # Drop needs:<agent> as well — once the PR is in human review, the
  # PO inbox claim has been consumed regardless of merge state.
  [[ -n "$LINKED_ISSUE" ]] && gh issue edit "$LINKED_ISSUE" --remove-label "needs:$AGENT" >/dev/null 2>&1 || true
fi
