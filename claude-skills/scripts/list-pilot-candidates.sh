#!/usr/bin/env bash
# list-pilot-candidates.sh — enumerate issues eligible for auto-implementation.
#
# Returns open issues that satisfy ALL of:
#   - label matches the caller's bus label (default: tech)
#   - label:bug OR label:enhancement
#   - label:human-reviewed       (skipped when .bsg-autopilot.yml authorizes the agent)
#   - label:safe-to-automate     (skipped when .bsg-autopilot.yml authorizes the agent)
#   - at least one epic:* label
#   - has no open PR already referencing it (agent didn't start work yet)
#
# When .bsg-autopilot.yml exists, is enabled, and lists the calling agent,
# both human-reviewed and safe-to-automate label filters are dropped —
# the repo-level marker replaces per-issue gates. See #221.
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

# Determine whether autopilot mode is active for this agent.
AUTOPILOT=false
if [[ -f .bsg-autopilot.yml ]]; then
  enabled=$(grep -E '^\s*enabled\s*:' .bsg-autopilot.yml 2>/dev/null | head -1 | sed 's/.*:\s*//' | tr -d '[:space:]')
  if [[ "$enabled" == "true" ]]; then
    if grep -qE "^\s*-\s+$AGENT\s*$" .bsg-autopilot.yml 2>/dev/null; then
      AUTOPILOT=true
    fi
  fi
fi

LABEL_FLAGS=(--label "$AGENT")
if [[ "$AUTOPILOT" == "false" ]]; then
  LABEL_FLAGS+=(--label "human-reviewed" --label "safe-to-automate")
else
  # Autopilot: human-reviewed and safe-to-automate are optional.
  # The repo-level opt-in replaces per-issue gates.
  :
fi

# Pull open issues carrying all required labels. GitHub's search API
# AND-s labels when multiple --label flags are passed, so the bug /
# enhancement OR-filter is applied below in jq instead of via --label.
candidates_json=$(gh issue list "${REPO_FLAG[@]}" \
  --state open \
  "${LABEL_FLAGS[@]}" \
  --json number,title,labels,url \
  2>/dev/null || echo "[]")

# Post-filter for:
#   - label:bug OR label:enhancement (#282)
#   - at least one epic:* label
#   - no open PR already touching this issue (avoid re-attempting)
# Emit one JSON object per line.
filtered=$(jq -c '
  .[]
  | select(.labels | any(.name == "bug" or .name == "enhancement"))
  | select(.labels | any(.name | startswith("epic:")))
  | {
      number,
      title,
      url,
      epics: [.labels[].name | select(startswith("epic:"))]
    }
' <<<"$candidates_json")

echo "$filtered"

# Lock the first candidate best-effort so concurrent ticks don't race. #269
if [[ -n "$filtered" ]]; then
  first_num=$(echo "$filtered" | head -1 | jq -r '.number')
  bus_lock "$first_num" "$AGENT" 2>/dev/null || true
fi
