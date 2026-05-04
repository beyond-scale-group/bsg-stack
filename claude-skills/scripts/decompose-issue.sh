#!/usr/bin/env bash
# decompose-issue.sh — split an oversized issue into child sub-issues that
# fit the autopilot pilot budget.
#
# `po-decompose-oversized.sh` flags issues whose estimated_loc exceeds
# `max_loc_per_issue` — they sit in the backlog because the pilot can't
# pick them up. This script is the mechanical executor for splitting:
# the PO agent (LLM) decides *how* to split (which sub-tasks, what
# titles), and this script files each sub-issue with the right
# inheritance.
#
# What it does:
#
#   1. Read the parent issue's bus label, milestone, and labels via gh.
#   2. For each --child "<title>" argument, file a sub-issue via
#      file-issue.sh with:
#        - parent's bus label (same agent ownership)
#        - parent's milestone
#        - type: enhancement
#        - label: parent:<parent-num>
#        - body referencing the parent number
#   3. Post a single comment on the parent listing all created
#      sub-issues so the audit trail is visible from one place.
#   4. (Optional) close the parent when --close-parent is passed —
#      the parent has been fully decomposed and the work tracker
#      moves to the children.
#
# The script is idempotent on the comment + close steps but NOT on
# child creation — calling it twice with the same --child arguments
# files duplicates. The PO agent is responsible for not re-decomposing
# an already-split issue (the `parent:<N>` label on existing children
# is the marker).
#
# Usage:
#   decompose-issue.sh --parent <num> \
#     --child "<sub-task title 1>" \
#     --child "<sub-task title 2>" \
#     [--child-body <num> "<body>"] \
#     [--close-parent] \
#     [--repo OWNER/NAME]
#
# The optional --child-body <index> "<body>" pairs let the caller
# attach a body to specific children (1-indexed). Children without
# bodies get a default `Child of #<parent>. See parent for context.`
#
# Emits one line per created sub-issue (JSON: number, url). Exit 0
# on success.

set -euo pipefail

PARENT=""
CHILDREN=()
CHILD_BODIES=()
CLOSE_PARENT=false
REPO_FLAG=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --parent) PARENT="$2"; shift 2 ;;
    --child) CHILDREN+=("$2"); shift 2 ;;
    --child-body)
      idx="$2"; body="$3"
      CHILD_BODIES[$idx]="$body"
      shift 3
      ;;
    --close-parent) CLOSE_PARENT=true; shift ;;
    --repo) REPO_FLAG=(--repo "$2"); shift 2 ;;
    -h|--help)
      sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "decompose-issue.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$PARENT" ]]; then
  echo "decompose-issue.sh: --parent <num> is required" >&2
  exit 2
fi

if [[ ${#CHILDREN[@]} -eq 0 ]]; then
  echo "decompose-issue.sh: at least one --child <title> is required" >&2
  exit 2
fi

# Read parent metadata.
parent_json=$(gh issue view "$PARENT" "${REPO_FLAG[@]}" \
  --json number,labels,milestone,title 2>/dev/null || echo "{}")

parent_title=$(jq -r '.title // empty' <<<"$parent_json")
parent_milestone=$(jq -r '.milestone.title // empty' <<<"$parent_json")
parent_bus=$(jq -r '
  .labels[] | select(.name == "tech" or .name == "qa" or .name == "seo") | .name
' <<<"$parent_json" | head -1)

if [[ -z "$parent_title" ]]; then
  echo "decompose-issue.sh: parent #${PARENT} not found or unreadable" >&2
  exit 1
fi

if [[ -z "$parent_bus" ]]; then
  echo "decompose-issue.sh: parent #${PARENT} has no bus label (tech/qa/seo) — refusing to decompose" >&2
  echo "decompose-issue.sh: run normalize-issue-labels.sh first to apply a bus label" >&2
  exit 1
fi

# Map bus_label → agent name for file-issue.sh --agent.
case "$parent_bus" in
  tech) parent_agent="tech-lead" ;;
  qa)   parent_agent="qa" ;;
  seo)  parent_agent="seo" ;;
  *)
    echo "decompose-issue.sh: unsupported bus label '${parent_bus}' on parent #${PARENT}" >&2
    exit 1
    ;;
esac

# Bootstrap the parent:<N> label on this repo (idempotent).
parent_label="parent:${PARENT}"
gh label create "$parent_label" "${REPO_FLAG[@]}" \
  --color "ededed" \
  --description "Sub-issue of #${PARENT} — created by decompose-issue.sh" \
  >/dev/null 2>&1 || true

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
created_numbers=()
created_urls=()

i=0
for title in "${CHILDREN[@]}"; do
  i=$((i + 1))
  body="${CHILD_BODIES[$i]:-}"
  if [[ -z "$body" ]]; then
    body="Child of #${PARENT} (\`${parent_title}\`).

This sub-issue was created by \`decompose-issue.sh\` to fit the autopilot pilot budget. See the parent for full context."
  fi

  file_issue_args=(
    --agent "$parent_agent"
    --filed-by "po-decompose"
    --type "enhancement"
    --title "$title"
    --body "$body"
    --label "$parent_label"
  )
  if [[ -n "$parent_milestone" ]]; then
    file_issue_args+=(--milestone "$parent_milestone")
  fi
  if [[ ${#REPO_FLAG[@]} -gt 0 ]]; then
    file_issue_args+=("${REPO_FLAG[@]}")
  fi

  url=$(bash "$SCRIPT_DIR/file-issue.sh" "${file_issue_args[@]}" 2>/dev/null || true)
  if [[ -z "$url" ]]; then
    echo "decompose-issue.sh: failed to file child '${title}' — aborting" >&2
    exit 1
  fi

  num=$(echo "$url" | grep -oE '[0-9]+$' || echo "")
  created_numbers+=("$num")
  created_urls+=("$url")
  jq -nc --arg n "$num" --arg u "$url" --arg t "$title" \
    '{number: ($n | tonumber? // null), url: $u, title: $t}'
done

# Post a single comment on the parent listing all children.
{
  echo "**Decomposed into ${#created_numbers[@]} sub-issue(s):**"
  echo
  i=0
  for num in "${created_numbers[@]}"; do
    echo "- #${num} — ${CHILDREN[$i]}"
    i=$((i + 1))
  done
  echo
  echo "Created by \`decompose-issue.sh\`. Each sub-issue inherits the parent's bus label (\`${parent_bus}\`) and milestone (\`${parent_milestone:-none}\`)."
} | gh issue comment "$PARENT" "${REPO_FLAG[@]}" --body-file - >/dev/null 2>&1 || true

if [[ "$CLOSE_PARENT" == "true" ]]; then
  gh issue close "$PARENT" "${REPO_FLAG[@]}" \
    --reason completed \
    --comment "Closed automatically — fully decomposed into sub-issues. Track work on the children." \
    >/dev/null 2>&1 || true
fi

exit 0
