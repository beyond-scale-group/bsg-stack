#!/usr/bin/env bash
# bus-handler.sh — per-agent claim handler for the GitHub coordination bus.
#
# Called at tick step (0) by each output:commit agent to process issues
# that carry the label "needs:<agent>". When the inbox is non-empty,
# the handler acknowledges each item with a structured marker comment
# so other agents and humans can trace the flow through GitHub labels.
#
# The handler is intentionally minimal: it acknowledges the claim and
# returns the issue numbers so the calling agent's tick can decide
# whether to attempt auto-implementation (via list-pilot-candidates.sh)
# or just log the handoff. Heavy per-role handler logic is deferred to
# #199 — this script is the activation layer for E7-bus-activation.
#
# Usage:
#   bash claude-skills/scripts/bus-handler.sh \
#     [--agent NAME] \
#     [--action acknowledge|log] \
#     [--repo OWNER/NAME]
#
# Outputs one issue number per line for each processed inbox item.
# Exits 0 always (empty inbox is not an error).
#
# Actions:
#   acknowledge  (default) — post a <!-- agent:<name> v1 kind:claim -->
#                            marker comment on each inbox issue and print
#                            the issue number to stdout.
#   log          — print the issue numbers to stdout without posting a
#                  comment (dry-run / audit mode).
#
# Requirements: gh (GitHub CLI), jq

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Source bus primitives (best-effort).
# shellcheck source=claude-skills/scripts/github-bus.sh
source "$SCRIPT_DIR/github-bus.sh" 2>/dev/null || true

AGENT="tech"
ACTION="acknowledge"
REPO_FLAG=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent)  AGENT="$2";  shift 2 ;;
    --action) ACTION="$2"; shift 2 ;;
    --repo)   REPO_FLAG=(--repo "$2"); shift 2 ;;
    -h|--help)
      sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "bus-handler.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done

# Fetch open issues with the needs:<agent> label.
# Exclude issues already locked by any agent (concurrent tick guard).
inbox_json=$(gh issue list "${REPO_FLAG[@]}" \
  --label "needs:${AGENT}" \
  --state open \
  --json number,labels,title \
  --limit 50 \
  2>/dev/null || echo "[]")

# Filter out locked issues client-side.
unlocked=$(jq -c '[
  .[]
  | select(
      .labels
      | map(.name)
      | map(startswith("agent:lock:"))
      | any
      | not
    )
]' <<<"$inbox_json")

count=$(jq 'length' <<<"$unlocked")
if [[ "$count" -eq 0 ]]; then
  exit 0
fi

# Process each unlocked inbox issue.
while IFS= read -r issue; do
  num=$(jq -r '.number' <<<"$issue")
  title=$(jq -r '.title' <<<"$issue")

  case "$ACTION" in
    acknowledge)
      # Post a machine-readable marker so the handoff is traceable.
      marker_body=$(printf 'agent: %s\naction: claim\ntitle: "%s"\nstatus: acknowledged' \
        "$AGENT" "$title")
      gh issue comment "${REPO_FLAG[@]}" "$num" \
        --body "$(printf '<!-- agent:%s v1 kind:claim -->\n%s\n<!-- /agent:%s -->' \
          "$AGENT" "$marker_body" "$AGENT")" \
        >/dev/null 2>&1 || true
      echo "$num"
      ;;
    log)
      echo "$num"
      ;;
    *)
      echo "bus-handler.sh: unknown action: $ACTION" >&2
      exit 2
      ;;
  esac
done < <(jq -c '.[]' <<<"$unlocked")
