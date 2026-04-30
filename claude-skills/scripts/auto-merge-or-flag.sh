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
  gh pr merge "$PR_NUMBER" --squash --delete-branch >/dev/null
  gh pr edit "$PR_NUMBER" --add-label human-reviewed >/dev/null 2>&1 || true
  gh pr edit "$PR_NUMBER" --remove-label needs-human-review >/dev/null 2>&1 || true
  [[ -n "$LINKED_ISSUE" ]] && bus_unlock "$LINKED_ISSUE" "$AGENT" || true
else
  echo "auto-merge-or-flag: PR #${PR_NUMBER} ← needs-human-review (default)"
  gh pr edit "$PR_NUMBER" --add-label needs-human-review >/dev/null
  [[ -n "$LINKED_ISSUE" ]] && bus_unlock "$LINKED_ISSUE" "$AGENT" || true
fi
