#!/usr/bin/env bash
# github-bus.sh — GitHub-as-coordination-bus primitives for BSG agents.
#
# Every BSG agent's `tick` action uses these functions to implement
# claim → work → handoff pipelines entirely through GitHub labels and
# comments. No central database, no message broker — GitHub is the bus.
#
# Label schema (see docs/label-taxonomy.md for the full reference):
#
#   needs:<agent>          Issue is waiting for <agent> to process it.
#   agent:lock:<agent>     Mutex: <agent>'s tick has claimed this issue
#                          and is currently working on it.
#   agent:done             Pipeline complete — no more agent hops needed.
#   agent:blocked          Human intervention required before pipeline
#                          can continue.
#
# Comment markers let agents leave machine-readable messages:
#
#   <!-- agent:<name> v1 kind:<kind> -->
#   <yaml body>
#   <!-- /agent:<name> -->
#
# Issue body manifest:
#   A fenced block labelled `agents-state` at the bottom of the issue
#   body holds the shared JSON state that every agent can read/update.
#
# Usage: source this file, then call the functions below.
#
#   source claude-skills/scripts/github-bus.sh
#   issues=$(bus_claim seo)
#   for num in $(echo "$issues" | jq -r '.[]'); do
#     bus_lock   "$num" seo
#     # … do work …
#     bus_handoff "$num" seo marketing "handed off after keyword audit"
#     bus_unlock  "$num" seo
#   done
#
# Requirements: gh (GitHub CLI), jq

set -euo pipefail

# ── Internal helpers ──────────────────────────────────────────────────────────

_bus_require() {
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || {
      echo "github-bus.sh: required command not found: $cmd" >&2
      return 1
    }
  done
}

_bus_repo() {
  gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null
}

# ── Claim ─────────────────────────────────────────────────────────────────────

# bus_claim <needs-label>
#
# Find open issues labeled "needs:<needs-label>" that are NOT currently
# locked by any agent. Prints a JSON array of issue numbers to stdout.
# Returns 0 even if the list is empty (empty inbox is not an error).
#
# Example:
#   issues=$(bus_claim seo)            # → [12, 34]
#   count=$(echo "$issues" | jq 'length')
bus_claim() {
  _bus_require gh jq
  local label="needs:${1:?bus_claim: needs-label required}"

  # Fetch open issues with the inbox label.
  # Filter client-side: exclude any that carry an agent:lock:* label so
  # two concurrent ticks never race on the same issue.
  gh issue list \
    --label "$label" \
    --state open \
    --json number,labels \
    --limit 100 \
    | jq '[
        .[]
        | select(
            .labels
            | map(.name)
            | map(startswith("agent:lock:"))
            | any
            | not
          )
        | .number
      ]'
}

# ── Lock / Unlock ─────────────────────────────────────────────────────────────

# bus_lock <issue-number> <agent-name>
#
# Add the "agent:lock:<agent-name>" label to prevent another concurrent
# tick from claiming the same issue. Always call bus_unlock when done
# (even on error — use a trap).
bus_lock() {
  _bus_require gh
  local num="${1:?bus_lock: issue number required}"
  local agent="${2:?bus_lock: agent name required}"
  gh issue edit "$num" --add-label "agent:lock:${agent}" >/dev/null
}

# bus_unlock <issue-number> <agent-name>
#
# Remove the "agent:lock:<agent-name>" label acquired by bus_lock.
bus_unlock() {
  _bus_require gh
  local num="${1:?bus_unlock: issue number required}"
  local agent="${2:?bus_unlock: agent name required}"
  gh issue edit "$num" --remove-label "agent:lock:${agent}" >/dev/null 2>&1 || true
}

# ── Handoff ───────────────────────────────────────────────────────────────────

# bus_handoff <issue-number> <from-label> <to-label> [comment]
#
# Swap the routing label on an issue to pass it to the next agent.
# - Removes "needs:<from-label>"
# - Adds    "needs:<to-label>"      (unless <to-label> == "done")
# - If done: removes any remaining "needs:*" labels and adds "agent:done"
# - Optionally posts <comment> as a plain GitHub comment (not a marker).
#
# Example:
#   bus_handoff 42 seo marketing "keyword audit complete"
#   bus_handoff 42 marketing done "all agent passes finished"
bus_handoff() {
  _bus_require gh jq
  local num="${1:?bus_handoff: issue number required}"
  local from="${2:?bus_handoff: from-label required}"
  local to="${3:?bus_handoff: to-label required}"
  local comment="${4:-}"

  gh issue edit "$num" --remove-label "needs:${from}" >/dev/null 2>&1 || true

  if [[ "$to" == "done" ]]; then
    # Remove all remaining needs:* labels and mark done.
    local needs_labels
    needs_labels=$(gh issue view "$num" --json labels \
      | jq -r '.labels[].name | select(startswith("needs:"))')
    for lbl in $needs_labels; do
      gh issue edit "$num" --remove-label "$lbl" >/dev/null 2>&1 || true
    done
    gh issue edit "$num" --add-label "agent:done" >/dev/null
  else
    gh issue edit "$num" --add-label "needs:${to}" >/dev/null
  fi

  if [[ -n "$comment" ]]; then
    gh issue comment "$num" --body "$comment" >/dev/null
  fi
}

# ── Structured marker comments ────────────────────────────────────────────────

# bus_post_marker <issue-number> <agent-name> <kind> <yaml-body>
#
# Post a machine-readable comment on an issue. The comment is wrapped in
# HTML markers so other agents can extract it without parsing prose.
#
# Format:
#   <!-- agent:<name> v1 kind:<kind> -->
#   <yaml-body>
#   <!-- /agent:<name> -->
#
# Example:
#   bus_post_marker 42 seo handoff "$(cat <<'EOF'
#   to: marketing
#   reason: keyword audit complete
#   artifact: seo/reports/2026-04-22-audit.md
#   EOF
#   )"
bus_post_marker() {
  _bus_require gh
  local num="${1:?bus_post_marker: issue number required}"
  local agent="${2:?bus_post_marker: agent name required}"
  local kind="${3:?bus_post_marker: kind required}"
  local body="${4:?bus_post_marker: yaml-body required}"

  local comment
  comment=$(printf '<!-- agent:%s v1 kind:%s -->\n%s\n<!-- /agent:%s -->' \
    "$agent" "$kind" "$body" "$agent")
  gh issue comment "$num" --body "$comment" >/dev/null
}

# bus_read_markers <issue-number> <agent-name>
#
# Extract all marker blocks posted by <agent-name> on the issue.
# Prints each YAML body separated by "---" (one document per marker).
#
# Example:
#   markers=$(bus_read_markers 42 seo)
bus_read_markers() {
  _bus_require gh jq
  local num="${1:?bus_read_markers: issue number required}"
  local agent="${2:?bus_read_markers: agent name required}"
  local open_tag="<!-- agent:${agent} v1"
  local close_tag="<!-- /agent:${agent} -->"

  gh issue view "$num" --comments --json comments \
    | jq -r '.comments[].body' \
    | awk \
        -v open="$open_tag" \
        -v close="$close_tag" \
        'BEGIN { inside=0; first=1 }
         $0 ~ open  { inside=1; next }
         $0 ~ close {
           if (!first) print "---"
           first=0
           inside=0
           next
         }
         inside { print }'
}

# ── Shared manifest (issue body JSON block) ───────────────────────────────────

# bus_set_manifest <issue-number> <json>
#
# Write (or overwrite) the `agents-state` fenced block at the bottom
# of the issue body. The block holds shared JSON state across all agents.
#
# The block looks like:
#   ```agents-state
#   { "phase": "seo", "owner": "seo", "blockers": [] }
#   ```
#
# Example:
#   bus_set_manifest 42 '{"phase":"marketing","owner":"marketing","blockers":[]}'
bus_set_manifest() {
  _bus_require gh jq
  local num="${1:?bus_set_manifest: issue number required}"
  local json="${2:?bus_set_manifest: json required}"

  # Validate JSON.
  echo "$json" | jq . >/dev/null || {
    echo "github-bus.sh: bus_set_manifest: invalid JSON" >&2
    return 1
  }

  local current_body
  current_body=$(gh issue view "$num" --json body --jq '.body')

  local block
  block=$(printf '```agents-state\n%s\n```' "$(echo "$json" | jq -c .)")

  # Replace existing block or append a new one.
  local new_body
  if echo "$current_body" | grep -q '```agents-state'; then
    new_body=$(echo "$current_body" \
      | awk -v block="$block" '
          /^```agents-state/ { in_block=1; print block; next }
          in_block && /^```$/ { in_block=0; next }
          !in_block { print }
        ')
  else
    new_body=$(printf '%s\n\n---\n\n%s' "$current_body" "$block")
  fi

  gh issue edit "$num" --body "$new_body" >/dev/null
}

# bus_get_manifest <issue-number>
#
# Extract and print the JSON from the `agents-state` block in the issue
# body. Prints `null` if no block is found.
#
# Example:
#   phase=$(bus_get_manifest 42 | jq -r '.phase')
bus_get_manifest() {
  _bus_require gh jq
  local num="${1:?bus_get_manifest: issue number required}"

  gh issue view "$num" --json body --jq '.body' \
    | awk '/^```agents-state/{found=1; next} found && /^```$/{exit} found{print}' \
    | jq -c '.' 2>/dev/null || echo 'null'
}
