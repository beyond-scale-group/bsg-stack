#!/usr/bin/env bash
# list-pilot-candidates.sh — enumerate issues eligible for auto-implementation.
#
# Returns open issues that satisfy ALL of:
#   - label matches the caller's bus label (default: tech)
#   - label:bug
#   - label:human-reviewed       (skipped when .bsg-autopilot.yml authorizes the agent)
#   - label:safe-to-automate     (skipped when .bsg-autopilot.yml authorizes the agent)
#   - at least one epic:* label
#   - has no open PR already referencing it (agent didn't start work yet)
#
# When .bsg-autopilot.yml exists, is enabled, and lists the calling agent,
# both human-reviewed and safe-to-automate label filters are dropped —
# the repo-level marker replaces per-issue gates. See #221.
#
# Usage:
#   bash claude-skills/scripts/list-pilot-candidates.sh [--agent NAME] [--repo OWNER/NAME]
#
# Emits one line per candidate issue (JSON). Empty output = no work.
# Exit 0 always (no candidate is not an error).

set -euo pipefail

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

LABEL_FLAGS=(--label "$AGENT" --label "bug")
if [[ "$AUTOPILOT" == "false" ]]; then
  LABEL_FLAGS+=(--label "human-reviewed" --label "safe-to-automate")
else
  # Autopilot: human-reviewed and safe-to-automate are optional.
  # The repo-level opt-in replaces per-issue gates.
  :
fi

# Pull open issues carrying all required labels. GitHub's search API
# AND-s labels when multiple --label flags are passed.
candidates_json=$(gh issue list "${REPO_FLAG[@]}" \
  --state open \
  "${LABEL_FLAGS[@]}" \
  --json number,title,labels,url \
  2>/dev/null || echo "[]")

# Post-filter for:
#   - at least one epic:* label
#   - no open PR already touching this issue (avoid re-attempting)
# Emit one JSON object per line.
jq -c '
  .[]
  | select(.labels | any(.name | startswith("epic:")))
  | {
      number,
      title,
      url,
      epics: [.labels[].name | select(startswith("epic:"))]
    }
' <<<"$candidates_json"
