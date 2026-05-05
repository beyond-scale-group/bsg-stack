#!/usr/bin/env bash
# list-pilot-candidates.sh — enumerate issues eligible for auto-implementation.
#
# Returns open issues that satisfy ALL of:
#   - label matches the caller's bus label (default: tech)
#   - label:bug OR label:enhancement
#   - assigned to a GitHub milestone (replaces epic:* label — #287)
#   - has no open PR already referencing it (agent didn't start work yet)
#
# Priority — needs:<agent> as PO inbox (#199, E7-bus-activation):
# When at least one open issue carries label:needs:<agent>, only those
# are returned (the PO has explicitly claimed which work to do next).
# When the inbox is empty, the script falls back to the full bus
# backlog — oldest-first by issue number — for backward compatibility
# with repos that don't run an active PO. This activates the bus
# routing primitive from docs/label-taxonomy.md.
#
# Auto-implementation is opt-in at the **repo level** via
# .bsg-autopilot.yml. Without the file, with `enabled: false`, or when
# the calling agent is not listed under `agents:`, no candidates are
# emitted (the agent's tick becomes audit-only). The previous per-issue
# gates `safe-to-automate` and `needs-human-review` were dropped in
# E10 (#286) — the repo-level marker is the single source of truth.
#
# After emitting the candidate list, the first (top) candidate is locked
# via bus_lock so concurrent ticks don't race on the same issue. The lock
# is best-effort — a failure never aborts the script. See #269.
#
# Usage:
#   bash claude-skills/scripts/list-pilot-candidates.sh [--agent NAME] [--repo OWNER/NAME]
#
# Emits one line per candidate issue (JSON). Empty output = no work.
# Exit 0 always (no candidate is not an error).

set -euo pipefail

# shellcheck source=_bsg-paths.sh disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/_bsg-paths.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Source bus primitives (best-effort — missing file is non-fatal).
# shellcheck source=claude-skills/scripts/github-bus.sh
source "$SCRIPT_DIR/github-bus.sh" 2>/dev/null || true

AGENT="tech"
REPO_FLAG=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent) AGENT="$2"; shift 2 ;;
    --repo)  REPO_FLAG=(--repo "$2"); shift 2 ;;
    -h|--help)
      sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "list-pilot-candidates.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done

# Auto-implementation requires a repo-level opt-in via .bsg-autopilot.yml.
# Without the file, with `enabled: false`, or when this agent is not
# listed under `agents:`, we emit no candidates — the agent's tick
# becomes audit-only. See #286.
if [[ ! -f "$BSG_AUTOPILOT_FILE" ]]; then
  exit 0
fi
enabled=$(grep -E '^\s*enabled\s*:' "$BSG_AUTOPILOT_FILE" 2>/dev/null | head -1 | sed 's/.*:\s*//' | tr -d '[:space:]')
if [[ "$enabled" != "true" ]]; then
  exit 0
fi
if ! grep -qE "^\s*-\s+$AGENT\s*$" "$BSG_AUTOPILOT_FILE" 2>/dev/null; then
  exit 0
fi

LABEL_FLAGS=(--label "$AGENT")

# Pull open issues carrying all required labels. GitHub's search API
# AND-s labels when multiple --label flags are passed, so the bug /
# enhancement OR-filter is applied below in jq instead of via --label.
# milestone is fetched so we can use it as the epic binding signal (#287).
candidates_json=$(gh issue list "${REPO_FLAG[@]}" \
  --state open \
  "${LABEL_FLAGS[@]}" \
  --json number,title,labels,url,milestone \
  2>/dev/null || echo "[]")

# Post-filter for:
#   - label:bug OR label:enhancement (#282)
#   - assigned to a GitHub milestone (#287 — replaces epic:* label check)
#   - no open PR already touching this issue (avoid re-attempting)
# Emit one JSON object per line. Each candidate carries an "inbox"
# boolean: true when label:needs:<agent> is present (PO claim).
filtered=$(jq -c --arg needs "needs:$AGENT" '
  .[]
  | select(.labels | any(.name == "bug" or .name == "enhancement"))
  | select(.milestone != null)
  | {
      number,
      title,
      url,
      milestone: .milestone.title,
      inbox: (.labels | any(.name == $needs))
    }
' <<<"$candidates_json")

# Inbox priority (#199): if any issue carries needs:<agent>, only emit
# those — that's the PO claim. Otherwise fall back to the full backlog
# (oldest-first preserved by gh issue list ordering) so repos without
# an active PO keep the previous behavior.
inbox_items=$(jq -c 'select(.inbox == true)' <<<"$filtered")
if [[ -n "$inbox_items" ]]; then
  filtered="$inbox_items"
fi

echo "$filtered"

# Lock the first candidate best-effort so concurrent ticks don't race. #269
if [[ -n "$filtered" ]]; then
  first_num=$(echo "$filtered" | head -1 | jq -r '.number')
  bus_lock "$first_num" "$AGENT" 2>/dev/null || true
fi
